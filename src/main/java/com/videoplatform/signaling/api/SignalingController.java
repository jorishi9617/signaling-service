package com.videoplatform.signaling.api;

import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Controller;
import org.springframework.validation.annotation.Validated;
import jakarta.validation.Valid;

import java.security.Principal;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

@Controller
@Validated
public class SignalingController {
    private final SimpMessagingTemplate messaging;

    public SignalingController(SimpMessagingTemplate messaging) { this.messaging = messaging; }

    @MessageMapping("/signaling")
    public void relay(@Payload @Valid SignalMessage message, Principal principal) {
        UUID senderId;
        try {
            senderId = UUID.fromString(principal.getName());
        } catch (RuntimeException exception) {
            throw new AccessDeniedException("Authenticated user is required");
        }
        if (senderId.equals(message.recipientId())) {
            throw new IllegalArgumentException("Cannot signal yourself");
        }
        Map<String, Object> outbound = new HashMap<>();
        outbound.put("type", message.type());
        outbound.put("callId", message.callId());
        outbound.put("senderId", senderId);
        outbound.put("payload", message.payload() == null ? Map.of() : message.payload());
        messaging.convertAndSendToUser(message.recipientId().toString(), "/queue/signaling", outbound);
    }
}
