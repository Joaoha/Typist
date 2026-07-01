// Typist brand mark: a bold "T" paired with a blinking text caret.
// Monochrome by default (inherits the current text color) so it works as a
// sidebar/nav glyph; pass a className to recolor.
const TypistMark = ({
  width,
  height,
  className,
  ...props
}: {
  width?: number | string;
  height?: number | string;
  className?: string;
  [key: string]: any;
}) => (
  <svg
    width={width || 120}
    height={height || 120}
    viewBox="0 0 120 120"
    className={className || "fill-text"}
    xmlns="http://www.w3.org/2000/svg"
    {...props}
  >
    {/* Letter T */}
    <path d="M24 26h60v16H59v52H45V42H24z" />
    {/* Blinking text caret */}
    <rect x="74" y="64" width="11" height="30" rx="2.5">
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

export default TypistMark;
