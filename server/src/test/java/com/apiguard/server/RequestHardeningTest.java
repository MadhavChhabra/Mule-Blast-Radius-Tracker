package com.apiguard.server;

import com.apiguard.server.service.RepoFetchService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
class RequestHardeningTest {

    @Autowired
    MockMvc mvc;

    @Test
    void blankRepoUrlIsRejectedWithFourHundred() throws Exception {
        mvc.perform(post("/api/sources/repos")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"url\":\"   \"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void missingAnalyzeSpecsAreRejectedWithFourHundred() throws Exception {
        mvc.perform(post("/api/analyze")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"api\":\"orders-api\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void githubWebhookIsRejectedWhenNoSigningSecretIsConfigured() throws Exception {
        mvc.perform(post("/webhooks/github")
                        .header("X-GitHub-Event", "pull_request")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"action\":\"opened\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void registeringAGitOptionAsARepoUrlIsRejectedUpFront() throws Exception {
        mvc.perform(post("/api/sources/repos")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"url\":\"--upload-pack=touch pwned.git\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void aRepoTokenIsNeverEchoedBackFromTheSourcesApi() throws Exception {
        mvc.perform(post("/api/sources/repos")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"url\":\"https://ghp_supersecrettoken@github.com/acme/orders-exp-api\"}"))
                .andExpect(status().isOk())
                .andExpect(content().string(not(containsString("ghp_supersecrettoken"))));

        mvc.perform(get("/api/sources"))
                .andExpect(status().isOk())
                .andExpect(content().string(not(containsString("ghp_supersecrettoken"))))
                .andExpect(content().string(containsString("github.com/acme/orders-exp-api")));

        mvc.perform(get("/api/audit?limit=50"))
                .andExpect(status().isOk())
                .andExpect(content().string(not(containsString("ghp_supersecrettoken"))));

        mvc.perform(post("/api/sources/repos/remove")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"url\":\"https://github.com/acme/orders-exp-api\"}"))
                .andExpect(status().isOk());
    }

    @Test
    void cloneUrlsThatLookLikeGitOptionsAreRejected() {
        // `--upload-pack=…` would otherwise reach `git clone` as an option and run a command.
        IllegalArgumentException e = assertThrows(IllegalArgumentException.class,
                () -> RepoFetchService.requireSafeCloneUrl("--upload-pack=touch pwned.git"));
        assertTrue(e.getMessage().contains("-"), e.getMessage());

        assertThrows(IllegalArgumentException.class,
                () -> RepoFetchService.requireSafeCloneUrl("ext::sh -c whoami.git"));
        assertThrows(IllegalArgumentException.class,
                () -> RepoFetchService.requireSafeCloneUrl("file:///etc/passwd.git"));
    }

    @Test
    void realCloneUrlsAreAccepted() {
        RepoFetchService.requireSafeCloneUrl("https://github.com/org/repo.git");
        RepoFetchService.requireSafeCloneUrl("http://internal.host/org/repo");
        RepoFetchService.requireSafeCloneUrl("ssh://git@bitbucket.org/ws/repo.git");
        RepoFetchService.requireSafeCloneUrl("git@github.com:org/repo.git");
    }
}
