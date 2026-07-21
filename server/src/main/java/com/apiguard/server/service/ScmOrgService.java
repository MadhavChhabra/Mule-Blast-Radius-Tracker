package com.apiguard.server.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.net.URI;
import java.net.URISyntaxException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.Locale;
import java.util.Optional;

@Service
public class ScmOrgService {

    private static final Logger log = LoggerFactory.getLogger(ScmOrgService.class);
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final int PAGE_SIZE = 100;

    public enum Host { GITHUB, BITBUCKET }

    public record OrgRef(Host host, String owner, String userInfo) {
    }

    public record RepoRef(String name, String webUrl, String cloneUrl) {
    }

    private final RestClient http;
    private final int maxRepos;

    public ScmOrgService(@Value("${apiguard.scm.max-org-repos:100}") int maxRepos) {
        this.maxRepos = maxRepos;
        SimpleClientHttpRequestFactory rf = new SimpleClientHttpRequestFactory();
        rf.setConnectTimeout(Duration.ofSeconds(10));
        rf.setReadTimeout(Duration.ofSeconds(30));
        this.http = RestClient.builder().requestFactory(rf).build();
    }

    public Optional<OrgRef> parse(String source) {
        if (source == null) {
            return Optional.empty();
        }
        String s = source.trim();
        if (!(s.startsWith("http://") || s.startsWith("https://")) || s.endsWith(".git")) {
            return Optional.empty();
        }
        URI uri;
        try {
            uri = new URI(s);
        } catch (URISyntaxException e) {
            return Optional.empty();
        }
        String hostName = uri.getHost() == null ? "" : uri.getHost().toLowerCase(Locale.ROOT);
        String path = uri.getPath() == null ? "" : uri.getPath();
        List<String> segments = new ArrayList<>();
        for (String seg : path.split("/")) {
            if (!seg.isBlank()) {
                segments.add(seg);
            }
        }
        if (hostName.equals("github.com") || hostName.equals("www.github.com")) {
            if (segments.size() == 1) {
                return Optional.of(new OrgRef(Host.GITHUB, segments.get(0), uri.getUserInfo()));
            }
            if (segments.size() == 2 && segments.get(0).equals("orgs")) {
                return Optional.of(new OrgRef(Host.GITHUB, segments.get(1), uri.getUserInfo()));
            }
            return Optional.empty();
        }
        if (hostName.equals("bitbucket.org") || hostName.equals("www.bitbucket.org")) {
            if (segments.size() == 1 && !segments.get(0).equals("workspace")) {
                return Optional.of(new OrgRef(Host.BITBUCKET, segments.get(0), uri.getUserInfo()));
            }
            return Optional.empty();
        }
        return Optional.empty();
    }

    public List<RepoRef> listRepos(OrgRef org) {
        List<RepoRef> repos = org.host() == Host.GITHUB ? listGitHub(org) : listBitbucket(org);
        if (repos.size() > maxRepos) {
            log.info("Org {} has {} repos; scanning the first {} (apiguard.scm.max-org-repos)",
                    org.owner(), repos.size(), maxRepos);
            repos = repos.subList(0, maxRepos);
        }
        return repos;
    }

    private List<RepoRef> listGitHub(OrgRef org) {

        try {
            return listGitHubPages("https://api.github.com/orgs/" + org.owner() + "/repos?type=all", org);
        } catch (NotFound e) {
            try {
                return listGitHubPages("https://api.github.com/users/" + org.owner() + "/repos", org);
            } catch (NotFound e2) {
                throw new IllegalArgumentException("GitHub org/user '" + org.owner()
                        + "' not found (private orgs need a token in the URL).");
            }
        }
    }

    private List<RepoRef> listGitHubPages(String base, OrgRef org) {
        List<RepoRef> all = new ArrayList<>();
        String token = gitHubToken(org.userInfo());
        for (int page = 1; all.size() <= maxRepos; page++) {
            String url = base + (base.contains("?") ? "&" : "?")
                    + "per_page=" + PAGE_SIZE + "&page=" + page + "&sort=pushed";
            String body;
            try {
                RestClient.RequestHeadersSpec<?> req = http.get().uri(url)
                        .header("Accept", "application/vnd.github+json");
                if (token != null) {
                    req = req.header("Authorization", "Bearer " + token);
                }
                body = req.retrieve().body(String.class);
            } catch (RestClientException e) {
                if (page == 1 && e.getMessage() != null && e.getMessage().contains("404")) {
                    throw new NotFound();
                }
                throw new IllegalArgumentException("Could not list repos for GitHub org/user '"
                        + org.owner() + "': " + shortHttpError(e));
            }
            List<RepoRef> pageRepos = parseGitHubReposPage(readTree(body), org.userInfo());
            all.addAll(pageRepos);
            if (countInPage(body) < PAGE_SIZE) {
                break;
            }
        }
        return all;
    }

    private static final class NotFound extends RuntimeException {
    }

    private List<RepoRef> listBitbucket(OrgRef org) {
        List<RepoRef> all = new ArrayList<>();
        String next = "https://api.bitbucket.org/2.0/repositories/" + org.owner() + "?pagelen=" + PAGE_SIZE;
        while (next != null && all.size() <= maxRepos) {
            String body;
            try {
                RestClient.RequestHeadersSpec<?> req = http.get().uri(next);
                if (org.userInfo() != null && org.userInfo().contains(":")) {
                    String basic = Base64.getEncoder()
                            .encodeToString(org.userInfo().getBytes(StandardCharsets.UTF_8));
                    req = req.header("Authorization", "Basic " + basic);
                }
                body = req.retrieve().body(String.class);
            } catch (RestClientException e) {
                throw new IllegalArgumentException("Could not list repos for Bitbucket workspace '"
                        + org.owner() + "': " + shortHttpError(e));
            }
            JsonNode root = readTree(body);
            all.addAll(parseBitbucketReposPage(root, org.userInfo()));
            JsonNode nextNode = root.get("next");
            next = nextNode == null || nextNode.isNull() ? null : nextNode.asText();
        }
        return all;
    }

    public static List<RepoRef> parseGitHubReposPage(JsonNode array, String userInfo) {
        List<RepoRef> repos = new ArrayList<>();
        if (array == null || !array.isArray()) {
            return repos;
        }
        for (JsonNode repo : array) {
            if (repo.path("archived").asBoolean(false)) {
                continue;
            }
            String name = repo.path("name").asText("");
            String cloneUrl = repo.path("clone_url").asText("");
            String webUrl = repo.path("html_url").asText(cloneUrl);
            if (!name.isEmpty() && !cloneUrl.isEmpty()) {
                repos.add(new RepoRef(name, webUrl, withUserInfo(cloneUrl, userInfo)));
            }
        }
        return repos;
    }

    public static List<RepoRef> parseBitbucketReposPage(JsonNode root, String userInfo) {
        List<RepoRef> repos = new ArrayList<>();
        JsonNode values = root == null ? null : root.get("values");
        if (values == null || !values.isArray()) {
            return repos;
        }
        for (JsonNode repo : values) {
            String name = repo.path("slug").asText(repo.path("name").asText(""));
            String cloneUrl = null;
            for (JsonNode clone : repo.path("links").path("clone")) {
                if ("https".equals(clone.path("name").asText())) {
                    cloneUrl = clone.path("href").asText();
                }
            }
            String webUrl = repo.path("links").path("html").path("href").asText(cloneUrl);
            if (!name.isEmpty() && cloneUrl != null && !cloneUrl.isEmpty()) {

                repos.add(new RepoRef(name, webUrl, withUserInfo(stripUserInfo(cloneUrl), userInfo)));
            }
        }
        return repos;
    }

    static String withUserInfo(String url, String userInfo) {
        if (userInfo == null || userInfo.isBlank()) {
            return url;
        }
        return url.replaceFirst("^(https?://)", "$1" + userInfo + "@");
    }

    static String stripUserInfo(String url) {
        return url.replaceFirst("^(https?://)[^@/]+@", "$1");
    }

    private static String gitHubToken(String userInfo) {
        if (userInfo == null || userInfo.isBlank()) {
            return null;
        }

        int colon = userInfo.indexOf(':');
        return colon >= 0 ? userInfo.substring(colon + 1) : userInfo;
    }

    private static int countInPage(String body) {
        JsonNode node = readTree(body);
        return node != null && node.isArray() ? node.size() : 0;
    }

    private static JsonNode readTree(String body) {
        try {
            return JSON.readTree(body == null ? "" : body);
        } catch (Exception e) {
            throw new IllegalArgumentException("Unexpected response from the code host (not JSON).");
        }
    }

    private static String shortHttpError(RestClientException e) {
        String msg = e.getMessage() == null ? "request failed" : e.getMessage();
        if (msg.contains("404")) {
            return "not found — check the org/workspace name (private orgs need a token in the URL)";
        }
        if (msg.contains("401") || msg.contains("403")) {
            return "access denied — for private orgs put a token in the URL, e.g. https://<token>@github.com/my-org";
        }
        int nl = msg.indexOf('\n');
        return nl > 0 ? msg.substring(0, nl) : msg;
    }
}
