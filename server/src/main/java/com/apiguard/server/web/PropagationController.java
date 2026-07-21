package com.apiguard.server.web;

import com.apiguard.server.service.PropagationService;
import jakarta.validation.constraints.NotBlank;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class PropagationController {

    private final PropagationService propagation;

    public PropagationController(PropagationService propagation) {
        this.propagation = propagation;
    }

    public record PropagationRequest(@NotBlank String api, @NotBlank String spec) {
    }

    @PostMapping("/api/propagation")
    public Dtos.PropagationResponse propagate(@RequestBody PropagationRequest req) {
        return propagation.propagate(req.api().trim(), req.spec());
    }
}
