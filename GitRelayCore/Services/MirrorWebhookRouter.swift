import Foundation

nonisolated enum MirrorWebhookRouter {
    static func decide(
        request: WebhookHTTPRequest,
        plans: [MirrorPlan],
        secretForMirror: (UUID) -> String?
    ) -> WebhookHandlingResult {
        WebhookPushMapper.decide(
            request: request,
            targets: plans.map { plan in
                WebhookPushMapper.HookTarget(
                    repoID: plan.id,
                    pathID: WebhookPushMapper.pathID(for: plan.id),
                    enabled: plan.policy.triggers.webhookEnabled
                )
            },
            secretForRepo: secretForMirror
        )
    }
}
