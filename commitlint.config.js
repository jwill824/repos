const { defineConfig } = require("cz-git");
const { execSync } = require("child_process");

// Debug flag - set to true to see debug logs
const DEBUG = false;

// Get modified files and extract scope
const getDefaultScope = () => {
	try {
		const gitStatus = execSync("git status --porcelain || true").toString();
		DEBUG && console.log("Git status:", gitStatus);

		// Look specifically for modified files (M)
		const modifiedFiles = gitStatus
			.split("\n")
			.filter((line) => line.match(/^( M|M |MM)/));

		DEBUG && console.log("Modified files:", modifiedFiles);

		if (modifiedFiles.length > 0) {
			// Get the first modified file's directory
			const firstFile = modifiedFiles[0].slice(3).trim();
			// Clean up the scope name
			const scope = firstFile
				.split("/")[0]
				.replace(/^\./, "") // Remove leading dot
				.replace(/^_/, "") // Remove leading underscore
				.toLowerCase(); // Normalize to lowercase

			DEBUG && console.log("Detected scope:", scope);
			return scope || "";
		}
	} catch (error) {
		console.error("Error detecting scope:", error);
	}
	return "";
};

const scopeComplete = getDefaultScope();

const suggestedScopes = scopeComplete ? [scopeComplete] : [];

module.exports = defineConfig({
	rules: {
		"subject-empty": [2, "never"],
	},
	prompt: {
		defaultScope: scopeComplete,
		customScopesAlign: !scopeComplete ? "top-bottom" : "bottom",
		alias: { fd: "docs: fix typos" },
		messages: {
			type: "Select the type of change that you're committing:",
			scope: "Denote the SCOPE of this change (optional):",
			customScope: "Denote the SCOPE of this change:",
			subject: "Write a SHORT, IMPERATIVE tense description of the change:\n",
			body: 'Provide a LONGER description of the change (optional). Use "|" to break new line:\n',
			breaking:
				'List any BREAKING CHANGES (optional). Use "|" to break new line:\n',
			footerPrefixSelect:
				"Select the ISSUES type of changeList by this change (optional):",
			customFooterPrefix: "Input ISSUES prefix:",
			footer: "List any ISSUES by this change. E.g.: #31, #34:\n",
			generatingByAI: "Generating your AI commit subject...",
			generatedSelectByAI: "Select suitable subject by AI generated:",
			confirmCommit: "Are you sure you want to proceed with the commit above?",
		},
		types: [
			{ value: "feat", name: "feat:     A new feature", emoji: ":sparkles:" },
			{ value: "fix", name: "fix:      A bug fix", emoji: ":bug:" },
			{
				value: "docs",
				name: "docs:     Documentation only changes",
				emoji: ":memo:",
			},
			{
				value: "style",
				name: "style:    Changes that do not affect the meaning of the code",
				emoji: ":lipstick:",
			},
			{
				value: "refactor",
				name: "refactor: A code change that neither fixes a bug nor adds a feature",
				emoji: ":recycle:",
			},
			{
				value: "perf",
				name: "perf:     A code change that improves performance",
				emoji: ":zap:",
			},
			{
				value: "test",
				name: "test:     Adding missing tests or correcting existing tests",
				emoji: ":white_check_mark:",
			},
			{
				value: "build",
				name: "build:    Changes that affect the build system or external dependencies",
				emoji: ":package:",
			},
			{
				value: "ci",
				name: "ci:       Changes to our CI configuration files and scripts",
				emoji: ":ferris_wheel:",
			},
			{
				value: "chore",
				name: "chore:    Other changes that don't modify src or test files",
				emoji: ":hammer:",
			},
			{
				value: "revert",
				name: "revert:   Reverts a previous commit",
				emoji: ":rewind:",
			},
		],
		useEmoji: false,
		emojiAlign: "center",
		useAI: false,
		aiNumber: 1,
		themeColorCode: "",
		scopes: suggestedScopes,
		suggestedScopes: suggestedScopes,
		allowCustomScopes: true,
		allowEmptyScopes: true,
		customScopesAlias: "custom",
		emptyScopesAlias: "empty",
		upperCaseSubject: false,
		markBreakingChangeMode: false,
		allowBreakingChanges: ["feat", "fix"],
		breaklineNumber: 100,
		breaklineChar: "|",
		skipQuestions: [],
		issuePrefixes: [
			{ value: "closed", name: "closed:   ISSUES has been processed" },
		],
		customIssuePrefixAlign: "top",
		emptyIssuePrefixAlias: "skip",
		customIssuePrefixAlias: "custom",
		allowCustomIssuePrefix: true,
		allowEmptyIssuePrefix: true,
		confirmColorize: true,
		scopeOverrides: undefined,
		defaultBody: "",
		defaultIssues: "",
		defaultSubject: "",
	},
});
