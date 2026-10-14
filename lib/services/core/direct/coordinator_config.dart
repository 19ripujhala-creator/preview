/// Native HTTP coordinator defaults from core/config.py (SD_CONFIG).
class CoordinatorConfig {
  const CoordinatorConfig({
    this.keepaliveInterval = 240,
    this.probeMaxAge = 30,
    this.mutationProbeMaxAge = 10,
    this.probeTimeout = 20,
    this.readDrainTimeout = 45,
    this.mutationDrainTimeout = 180,
    this.authTimeout = 150,
    this.recoverCooldown = 10,
    this.autoRecoveryLimit = 0,
    this.autoRecoveryWindow = 300,
    this.maxAttempts = 3,
    this.defaultOpTimeout = 75,
    this.defaultLeaseWait = 35,
    this.readCancelGrace = 3,
    this.authSettleGrace = 10,
    this.mutationSettleTimeout = 15,
    this.mutationVerifyTimeout = 60,
    this.probeConfirmDelay = 1,
    this.shutdownTimeout = 180,
    this.degradedRecoveryWindow = 600,
    this.degradedRecoveryCooldown = 60,
    this.degradedRecoveryLimit = 2,
  });
  final double keepaliveInterval,
      probeMaxAge,
      mutationProbeMaxAge,
      probeTimeout;
  final double readDrainTimeout,
      mutationDrainTimeout,
      authTimeout,
      recoverCooldown;
  final int autoRecoveryLimit, maxAttempts, degradedRecoveryLimit;
  final double autoRecoveryWindow, defaultOpTimeout, defaultLeaseWait;
  final double readCancelGrace, authSettleGrace, mutationSettleTimeout;
  final double mutationVerifyTimeout, probeConfirmDelay, shutdownTimeout;
  final double degradedRecoveryWindow, degradedRecoveryCooldown;

  void validate() {
    if (maxAttempts < 1 || autoRecoveryLimit < 0 || degradedRecoveryLimit < 1) {
      throw ArgumentError('Invalid coordinator attempt limits.');
    }
    for (final value in [
      keepaliveInterval,
      probeMaxAge,
      mutationProbeMaxAge,
      probeTimeout,
      readDrainTimeout,
      mutationDrainTimeout,
      authTimeout,
      recoverCooldown,
      autoRecoveryWindow,
      defaultOpTimeout,
      defaultLeaseWait,
      readCancelGrace,
      authSettleGrace,
      mutationSettleTimeout,
      mutationVerifyTimeout,
      probeConfirmDelay,
      shutdownTimeout,
      degradedRecoveryWindow,
      degradedRecoveryCooldown,
    ]) {
      if (!value.isFinite || value < 0) {
        throw ArgumentError(
          'Coordinator durations must be finite and nonnegative.',
        );
      }
    }
    for (final value in [
      probeTimeout,
      authTimeout,
      defaultOpTimeout,
      readCancelGrace,
      mutationSettleTimeout,
      mutationVerifyTimeout,
      shutdownTimeout,
    ]) {
      if (value <= 0)
        throw ArgumentError('Coordinator deadline must be positive.');
    }
  }
}
