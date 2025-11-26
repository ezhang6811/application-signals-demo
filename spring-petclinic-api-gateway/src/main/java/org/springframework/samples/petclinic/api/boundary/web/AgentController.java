package org.springframework.samples.petclinic.api.boundary.web;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.samples.petclinic.api.application.NutritionServiceClient;
import org.springframework.samples.petclinic.api.dto.PetNutrition;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Mono;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.bedrockagentcore.BedrockAgentCoreClient;
import software.amazon.awssdk.services.bedrockagentcore.model.InvokeAgentRuntimeRequest;
import software.amazon.awssdk.services.bedrockagentcore.model.InvokeAgentRuntimeResponse;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

@Slf4j
@RestController
@RequestMapping("/api/agent")
public class AgentController {

    private String primaryAgentArn = "arn:aws:bedrock-agentcore:us-east-1:140023401067:runtime/pet_clinic_agent-1237f9CoGU";

    private String nutritionAgentArn = "arn:aws:bedrock-agentcore:us-east-1:140023401067:runtime/pet_clinic_agent-1237f9CoGU";

    private String awsRegion = "us-east-1";

    private final BedrockAgentCoreClient bedrockClient;
    private final String sessionId;

    @Autowired
    private NutritionServiceClient nutritionServiceClient;

    public AgentController(String region) {
        this.bedrockClient = BedrockAgentCoreClient.builder()
                .region(Region.of(awsRegion))
                .credentialsProvider(software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider.builder().build())
                .build();
        this.sessionId = "pet-clinic-web-session-" + UUID.randomUUID().toString();
    }

    @PostMapping(value = "/ask", produces = MediaType.APPLICATION_JSON_VALUE)
    public Mono<Map<String, Object>> askAgent(@RequestBody Map<String, String> request) {
        String query = request.get("query");
        String petType = request.get("petType");
        
        if (query == null || query.trim().isEmpty()) {
            return Mono.error(new ResponseStatusException(HttpStatus.BAD_REQUEST, "Query is required"));
        }

        if (primaryAgentArn == null || primaryAgentArn.isEmpty()) {
            return Mono.error(new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Agent ARN not configured"));
        }

        if (petType != null && !petType.trim().isEmpty()) {
            return nutritionServiceClient.getPetNutrition(petType)
                    .flatMap(nutrition -> Mono.fromCallable(() -> invokeAgent(query, nutrition)))
                    .switchIfEmpty(Mono.fromCallable(() -> invokeAgent(query, null)));
        }

        return Mono.fromCallable(() -> invokeAgent(query, null));
    }

    private Map<String, Object> invokeAgent(String query, PetNutrition nutrition) throws Exception {
        String prompt = buildPrompt(query, nutrition);
        String payload = String.format("{\"prompt\": \"%s\"}", escapeJson(prompt));

        InvokeAgentRuntimeRequest invokeRequest = InvokeAgentRuntimeRequest.builder()
                .agentRuntimeArn("arn:aws:bedrock-agentcore:us-east-1:140023401067:runtime/pet_clinic_agent-1237f9CoGU")
                .qualifier("DEFAULT")
                .runtimeSessionId(sessionId)
                .contentType("application/json")
                .accept("application/json")
                .payload(SdkBytes.fromUtf8String(payload))
                .build();

        try (ResponseInputStream<InvokeAgentRuntimeResponse> responseStream = bedrockClient.invokeAgentRuntime(invokeRequest)) {
            String responseBody = new BufferedReader(
                    new InputStreamReader(responseStream, StandardCharsets.UTF_8))
                    .lines()
                    .collect(Collectors.joining("\n"));

            String formattedResponse = formatForUI(responseBody);

            return Map.of(
                    "query", query,
                    "response", formattedResponse,
                    "sessionId", sessionId
            );
        }
    }

    private String escapeJson(String str) {
        return str.replace("\\", "\\\\")
                  .replace("\"", "\\\"")
                  .replace("\n", "\\n")
                  .replace("\r", "\\r")
                  .replace("\t", "\\t");
    }

    private String buildPrompt(String query, PetNutrition nutrition) {
        StringBuilder prompt = new StringBuilder(query);
        
        prompt.append("\n\nIMPORTANT INSTRUCTIONS:");
        prompt.append("\n- Only recommend products that exist in the provided nutrition data below.");
        prompt.append("\n- If nutrition data is unavailable or empty, inform the customer that nutrition information is not available for this pet type instead of making recommendations.");
        prompt.append("\n- Never fabricate or guess product recommendations.");
        
        if (nutrition != null && nutrition.getFacts() != null && !nutrition.getFacts().isEmpty()) {
            prompt.append("\n\nAvailable Nutrition Information:\n");
            prompt.append(nutrition.getFacts());
        } else {
            prompt.append("\n\nNutrition Data: NOT AVAILABLE - Do not make product recommendations.");
        }
        
        return prompt.toString();
    }

    private String formatForUI(String response) {
        if (response == null || response.isEmpty()) {
            return response;
        }
        String formatted = response.trim();
        if (formatted.startsWith("\"") && formatted.endsWith("\"")) {
            formatted = formatted.substring(1, formatted.length() - 1);
        }
        return formatted.replace("\\n", "\n").replace("\\\"", "\"").replace("\\\\", "\\");
    }
}
