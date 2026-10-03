package com.videoplatform.signaling.security;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.util.UUID;

@Component
public class JwtService {
    private final SecretKey key;

    public JwtService(@Value("${security.jwt.secret}") String secret) {
        byte[] bytes = Decoders.BASE64.decode(secret);
        if (bytes.length < 32) {
            throw new IllegalArgumentException("security.jwt.secret must decode to at least 32 bytes");
        }
        this.key = Keys.hmacShaKeyFor(bytes);
    }

    public UUID subject(String token) {
        return UUID.fromString(claims(token).getSubject());
    }

    public boolean isValid(String token) {
        try {
            String subject = claims(token).getSubject();
            if (subject == null) {
                return false;
            }
            UUID.fromString(subject);
            return true;
        } catch (io.jsonwebtoken.JwtException | IllegalArgumentException exception) {
            return false;
        }
    }

    private Claims claims(String token) {
        return Jwts.parser().verifyWith(key).build().parseSignedClaims(token).getPayload();
    }
}
