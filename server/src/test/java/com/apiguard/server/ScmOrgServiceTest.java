package com.apiguard.server;

import com.apiguard.server.service.ScmOrgService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ScmOrgServiceTest {

    private final ScmOrgService svc = new ScmOrgService(100);
    private static final ObjectMapper JSON = new ObjectMapper();

    @Test
    void detectsGitHubOrgAndUserUrls() {
        var org = svc.parse("https://github.com/mulesoft").orElseThrow();
        assertEquals(ScmOrgService.Host.GITHUB, org.host());
        assertEquals("mulesoft", org.owner());

        var orgsForm = svc.parse("https://github.com/orgs/mulesoft/").orElseThrow();
        assertEquals("mulesoft", orgsForm.owner());

        var withToken = svc.parse("https://ghp_abc123@github.com/acme").orElseThrow();
        assertEquals("ghp_abc123", withToken.userInfo());
    }

    @Test
    void repoUrlsAndLocalPathsAreNotOrgs() {
        assertTrue(svc.parse("https://github.com/mulesoft/orders-exp-api").isEmpty(), "repo URL");
        assertTrue(svc.parse("https://github.com/mulesoft/orders-exp-api.git").isEmpty(), "repo .git URL");
        assertTrue(svc.parse("C:/work/mule-projects").isEmpty(), "local path");
        assertTrue(svc.parse("https://gitlab.com/whatever").isEmpty(), "unsupported host");
        assertTrue(svc.parse(null).isEmpty(), "null");
    }

    @Test
    void detectsBitbucketWorkspace() {
        var ws = svc.parse("https://bitbucket.org/acme-integration").orElseThrow();
        assertEquals(ScmOrgService.Host.BITBUCKET, ws.host());
        assertEquals("acme-integration", ws.owner());
        assertTrue(svc.parse("https://bitbucket.org/acme/orders-sapi").isEmpty(), "repo URL is not a workspace");
    }

    @Test
    void parsesGitHubReposPageAndSkipsArchived() throws Exception {
        String json = """
                [
                  {"name":"orders-exp-api","clone_url":"https://github.com/acme/orders-exp-api.git",
                   "html_url":"https://github.com/acme/orders-exp-api","archived":false},
                  {"name":"legacy-api","clone_url":"https://github.com/acme/legacy-api.git",
                   "html_url":"https://github.com/acme/legacy-api","archived":true}
                ]""";
        List<ScmOrgService.RepoRef> repos = ScmOrgService.parseGitHubReposPage(JSON.readTree(json), "tok");
        assertEquals(1, repos.size());
        assertEquals("orders-exp-api", repos.get(0).name());
        assertEquals("https://github.com/acme/orders-exp-api", repos.get(0).webUrl());
        assertEquals("https://tok@github.com/acme/orders-exp-api.git", repos.get(0).cloneUrl());
    }

    @Test
    void parsesBitbucketReposPage() throws Exception {
        String json = """
                {"values":[
                   {"slug":"orders-sapi","links":{
                      "clone":[{"name":"https","href":"https://user@bitbucket.org/acme/orders-sapi.git"},
                               {"name":"ssh","href":"git@bitbucket.org:acme/orders-sapi.git"}],
                      "html":{"href":"https://bitbucket.org/acme/orders-sapi"}}}],
                 "next":"https://api.bitbucket.org/2.0/repositories/acme?page=2"}""";
        List<ScmOrgService.RepoRef> repos =
                ScmOrgService.parseBitbucketReposPage(JSON.readTree(json), "user:app-pass");
        assertEquals(1, repos.size());
        assertEquals("orders-sapi", repos.get(0).name());

        assertEquals("https://user:app-pass@bitbucket.org/acme/orders-sapi.git", repos.get(0).cloneUrl());
        assertEquals("https://bitbucket.org/acme/orders-sapi", repos.get(0).webUrl());
    }
}
