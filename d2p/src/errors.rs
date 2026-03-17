/// Typed errors for the d2p deployment tool.
#[derive(Debug, thiserror::Error)]
pub enum D2pError {
    /// forge or cast binary not found on PATH.
    #[error("process not found on PATH: {0}")]
    ProcessNotFound(String),

    /// Subprocess exited with non-zero status.
    #[error("subprocess exited non-zero: {stderr}")]
    NonZeroExit { stderr: String },

    /// Could not extract address or tx hash from command output.
    #[error("failed to parse deploy output: {0}")]
    ParseFailure(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_d2p_error_variants() {
        let e1 = D2pError::ProcessNotFound("forge".to_string());
        assert_eq!(e1.to_string(), "process not found on PATH: forge");

        let e2 = D2pError::NonZeroExit { stderr: "exit 1".to_string() };
        assert_eq!(e2.to_string(), "subprocess exited non-zero: exit 1");

        let e3 = D2pError::ParseFailure("no address".to_string());
        assert_eq!(e3.to_string(), "failed to parse deploy output: no address");

        // Verify std::error::Error is implemented (thiserror generates this)
        let _: &dyn std::error::Error = &e1;
    }
}
