package com.videoplatform.signaling.config;

import com.videoplatform.signaling.security.JwtService;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.config.ChannelRegistration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageHeaderAccessor;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;

import java.util.List;

@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfiguration implements WebSocketMessageBrokerConfigurer {
    private final JwtService jwtService;
    private final List<String> allowedOrigins;

    public WebSocketConfiguration(JwtService jwtService,
            @org.springframework.beans.factory.annotation.Value("${app.cors.allowed-origins}") String allowedOrigins) {
        this.jwtService = jwtService;
        this.allowedOrigins = List.of(allowedOrigins.split("\\s*,\\s*"));
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        registry.addEndpoint("/ws").setAllowedOrigins(allowedOrigins.toArray(String[]::new));
    }

    @Override
    public void configureMessageBroker(MessageBrokerRegistry registry) {
        registry.setApplicationDestinationPrefixes("/app");
        registry.setUserDestinationPrefix("/user");
        registry.enableSimpleBroker("/queue");
    }

    @Override
    public void configureClientInboundChannel(ChannelRegistration registration) {
        registration.interceptors(new ChannelInterceptor() {
            @Override
            public Message<?> preSend(Message<?> message, MessageChannel channel) {
                StompHeaderAccessor accessor = MessageHeaderAccessor.getAccessor(message, StompHeaderAccessor.class);
                if (accessor != null && StompCommand.CONNECT.equals(accessor.getCommand())) {
                    List<String> headers = accessor.getNativeHeader("Authorization");
                    if (headers == null || headers.isEmpty() || !headers.getFirst().startsWith("Bearer ")) {
                        throw new IllegalArgumentException("A bearer token is required to connect");
                    }
                    String token = headers.getFirst().substring(7);
                    if (!jwtService.isValid(token)) {
                        throw new IllegalArgumentException("Invalid bearer token");
                    }
                    String userId = jwtService.subject(token).toString();
                    accessor.setUser(new UsernamePasswordAuthenticationToken(userId, null, List.of()));
                }
                return message;
            }
        });
    }
}
