package com.apiguard.server.web;

import com.apiguard.server.service.EndpointInspectorService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class EndpointInspectorController {

    private final EndpointInspectorService inspector;

    public EndpointInspectorController(EndpointInspectorService inspector) {
        this.inspector = inspector;
    }

    @GetMapping("/api/endpoint")
    public Dtos.EndpointInspectDto inspect(@RequestParam String api,
                                           @RequestParam(required = false) String endpoint) {
        return inspector.inspect(api.trim(), endpoint);
    }
}
