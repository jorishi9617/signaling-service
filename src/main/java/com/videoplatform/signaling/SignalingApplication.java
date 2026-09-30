package com.videoplatform.signaling;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.security.servlet.UserDetailsServiceAutoConfiguration;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(scanBasePackages = "com.videoplatform", exclude = UserDetailsServiceAutoConfiguration.class)
public class SignalingApplication {
    public static void main(String[] args) {
        SpringApplication.run(SignalingApplication.class, args);
    }
}
