package com.videoplatform.signaling.api;

public enum SignalType {
    CALL_REQUEST, CALL_ACCEPT, CALL_REJECT, CALL_END,
    WEBRTC_OFFER, WEBRTC_ANSWER, ICE_CANDIDATE
}
