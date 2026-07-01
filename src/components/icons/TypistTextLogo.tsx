import React from "react";

// The brand wordmark — kept as a constant (not inline JSX text) so the i18n
// lint rule doesn't treat the product name as translatable copy.
const WORDMARK = "Typist";

// Typist wordmark. Rendered as live text so it inherits the brand tokens
// (--color-logo-primary fill, --color-logo-stroke outline) and stays crisp at
// any size, with a blinking caret echoing the app mark.
const TypistTextLogo = ({
  width,
  height,
  className,
}: {
  width?: number;
  height?: number;
  className?: string;
}) => {
  return (
    <svg
      width={width}
      height={height}
      className={className}
      viewBox="0 0 360 110"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <text
        x="2"
        y="82"
        fontFamily="'Inter', 'Helvetica Neue', Arial, system-ui, sans-serif"
        fontSize="88"
        fontWeight="800"
        letterSpacing="-4"
        className="logo-primary"
        stroke="var(--color-logo-stroke)"
        strokeWidth="1.5"
      >
        {WORDMARK}
      </text>
      {/* Caret after the wordmark */}
      <rect x="300" y="30" width="13" height="56" rx="3" className="logo-primary">
        <animate
          attributeName="opacity"
          values="1;1;0;0;1"
          keyTimes="0;0.45;0.5;0.95;1"
          dur="1.06s"
          repeatCount="indefinite"
        />
      </rect>
    </svg>
  );
};

export default TypistTextLogo;
