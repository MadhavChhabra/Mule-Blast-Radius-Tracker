package com.apiguard.server.web;

import org.junit.jupiter.api.Test;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class SearchRankingTest {

    private static Set<String> names(String... n) {
        return new LinkedHashSet<>(List.of(n));
    }

    @Test
    void theExactMatchLeadsEvenWhenItWasDiscoveredLast() {
        Set<String> all = names(
                "billing-orders-sys-api", "orders-exp-api-v2", "legacy-orders", "orders");

        List<SearchController.ApiHit> hits = SearchController.rankedApiHits(all, "orders");

        assertThat(hits.get(0).api()).isEqualTo("orders");
        assertThat(hits.get(1).api()).isEqualTo("orders-exp-api-v2");
    }

    @Test
    void aWordBoundaryBeatsAMatchBuriedMidName() {
        Set<String> all = names("xxordersyy-api", "billing-orders-api");

        List<SearchController.ApiHit> hits = SearchController.rankedApiHits(all, "orders");

        assertThat(hits.get(0).api()).isEqualTo("billing-orders-api");
    }

    @Test
    void aThousandApiEstateStillSurfacesTheOneYouTyped() {
        Set<String> all = new LinkedHashSet<>();
        for (int i = 0; i < 1000; i++) {
            all.add("svc" + i + "-orders-api");
        }
        // The one the user means is added last, well past the twenty-result cap.
        all.add("orders-api");

        List<SearchController.ApiHit> hits = SearchController.rankedApiHits(all, "orders-api");

        assertThat(hits).hasSize(20);
        assertThat(hits.get(0).api()).isEqualTo("orders-api");
    }

    @Test
    void anEmptyQueryListsAlphabeticallyRatherThanByInsertionAccident() {
        Set<String> all = names("zebra-api", "alpha-api", "middle-api");

        List<SearchController.ApiHit> hits = SearchController.rankedApiHits(all, "");

        assertThat(hits).extracting(SearchController.ApiHit::api)
                .containsExactly("alpha-api", "middle-api", "zebra-api");
    }
}
