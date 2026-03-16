import eslint from "@eslint/js";
import tseslint from "typescript-eslint";
import reactHooks from "eslint-plugin-react-hooks";

export default tseslint.config(
  eslint.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  ...tseslint.configs.stylisticTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    plugins: {
      "react-hooks": reactHooks,
    },
    rules: {
      // Prefer type over interface
      "@typescript-eslint/consistent-type-definitions": ["error", "type"],

      // React hooks rules
      "react-hooks/rules-of-hooks": "error",
      "react-hooks/exhaustive-deps": "warn",

      // Type imports
      "@typescript-eslint/consistent-type-imports": [
        "error",
        { prefer: "type-imports", fixStyle: "inline-type-imports" },
      ],

      // Relax some strict rules
      "@typescript-eslint/no-confusing-void-expression": "off",
      "@typescript-eslint/restrict-template-expressions": [
        "error",
        { allowNumber: true, allowBoolean: true },
      ],

      // Require braces for all control statements
      curly: ["error", "all"],

      // Disallow else-if chains
      "no-restricted-syntax": [
        "error",
        {
          selector: "IfStatement > IfStatement.alternate",
          message: "Use switch-case or object lookup instead of else-if",
        },
      ],
    },
  },
  {
    ignores: ["dist/**", "*.config.js"],
  }
);
