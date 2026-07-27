import React, { Component, ErrorInfo, ReactNode } from "react";
import { useTranslation } from "react-i18next";

type ErrorBoundaryProps = {
  children: ReactNode;
  fallback?: ReactNode;
};

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo): void {
    console.error("Uncaught error:", error, errorInfo);
  }

  private handleReset = (): void => {
    this.setState({ hasError: false, error: null });
    window.location.reload();
  };

  render(): ReactNode {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback;
      }

      return <ErrorFallback error={this.state.error} onReset={this.handleReset} />;
    }

    return this.props.children;
  }
}

const ErrorFallback: React.FC<{
  error: Error | null;
  onReset: () => void;
}> = ({ error, onReset }) => {
  const { t } = useTranslation();

  return (
    <div className="h-screen flex items-center justify-center bg-background px-4">
      <div className="max-w-md w-full text-center">
        <h2 className="text-lg font-semibold mb-2 text-error">
          {t("errors.appCrashed", { defaultValue: "Something went wrong" })}
        </h2>
        <p className="text-sm text-muted-foreground mb-4">
          {error?.message || t("errors.anErrorOccurred", { defaultValue: "An unexpected error occurred." })}
        </p>
        <button
          onClick={onReset}
          className="px-4 py-2 bg-primary text-primary-foreground rounded-md text-sm font-medium hover:bg-primary/90 transition-colors"
        >
          {t("errors.reloadApp", { defaultValue: "Reload App" })}
        </button>
      </div>
    </div>
  );
};

export default ErrorBoundary;