package com.videoplatform.signaling.api;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.Map;
import java.util.UUID;

public record SignalMessage(
        @NotNull SignalType type,
        @NotNull UUID callId,
        @NotNull UUID recipientId,
        @Size(max = 20) Map<String, Object> payload) {}
