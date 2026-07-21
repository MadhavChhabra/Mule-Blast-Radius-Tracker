package com.apiguard.server;

import com.apiguard.server.web.Dtos;
import com.apiguard.server.web.GraphExportController;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Method;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class GraphExportControllerTest {

    @Test
    void svgLaysOutNodesByLayerAndDrawsEdges() throws Exception {
        Dtos.GraphDto g = new Dtos.GraphDto(
                List.of(
                        new Dtos.GraphNode("web", "web", "APP", false, 1, 0, "team-a", List.of()),
                        new Dtos.GraphNode("orders-exp-api", "orders", "EXPERIENCE", true, 1, 1, null, List.of()),
                        new Dtos.GraphNode("orders-sys-api", "orders-sys", "SYSTEM", true, 0, 1, null, List.of())
                ),
                List.of(
                        new Dtos.GraphEdge("web", "orders-exp-api", "depends on", "safe", List.of("GET /orders")),
                        new Dtos.GraphEdge("orders-exp-api", "orders-sys-api", "depends on", "breaking", List.of())
                ));

        Method m = GraphExportController.class.getDeclaredMethod("renderSvg", Dtos.GraphDto.class);
        m.setAccessible(true);
        String svg = (String) m.invoke(null, g);

        assertTrue(svg.startsWith("<svg xmlns"), svg.substring(0, Math.min(80, svg.length())));
        assertTrue(svg.contains(">APP<"), "layer heading APP");
        assertTrue(svg.contains(">EXPERIENCE<"), "layer heading EXPERIENCE");
        assertTrue(svg.contains(">SYSTEM<"), "layer heading SYSTEM");
        assertTrue(svg.contains("class=\"node app\""), "APP node class present");
        assertTrue(svg.contains("edge edge-breaking"), "breaking edge class present");
        assertTrue(svg.contains("edge edge-safe"), "safe edge class present");
        assertTrue(svg.contains(">orders<"), "node label present");
        assertEquals(-1, svg.indexOf(">UNKNOWN<"), "no empty layer column heading");
    }
}
