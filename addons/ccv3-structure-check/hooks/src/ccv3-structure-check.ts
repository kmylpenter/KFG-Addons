import * as fs from 'fs';
import * as path from 'path';

interface SessionStartInput {
  source?: 'startup' | 'resume' | 'clear' | 'compact';
  type?: 'startup' | 'resume' | 'clear' | 'compact'; // Legacy
  session_id: string;
}

interface HookOutput {
  result: 'continue' | 'block';
  message?: string;
}

const CCV3_STRUCTURE = [
  'thoughts',
  'thoughts/ledgers',
  'thoughts/shared',
  'thoughts/shared/handoffs',
  'thoughts/shared/plans'
];

async function main() {
  const input: SessionStartInput = JSON.parse(await readStdin());
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();

  // Only run on startup (not on resume/clear/compact)
  const sessionType = input.source || input.type;
  if (sessionType !== 'startup') {
    console.log(JSON.stringify({ result: 'continue' }));
    return;
  }

  // Check if thoughts/ exists at all
  const thoughtsDir = path.join(projectDir, 'thoughts');
  if (fs.existsSync(thoughtsDir)) {
    // Structure exists - nothing to do
    console.log(JSON.stringify({ result: 'continue' }));
    return;
  }

  // Structure missing - auto-create
  const created: string[] = [];

  for (const dir of CCV3_STRUCTURE) {
    const fullPath = path.join(projectDir, dir);
    if (!fs.existsSync(fullPath)) {
      fs.mkdirSync(fullPath, { recursive: true });
      created.push(dir);
    }
  }

  // Create .gitkeep files to preserve empty dirs
  const gitkeepDirs = [
    'thoughts/ledgers',
    'thoughts/shared/handoffs',
    'thoughts/shared/plans'
  ];

  for (const dir of gitkeepDirs) {
    const gitkeepPath = path.join(projectDir, dir, '.gitkeep');
    if (!fs.existsSync(gitkeepPath)) {
      fs.writeFileSync(gitkeepPath, '');
    }
  }

  // Create README for thoughts/
  const readmePath = path.join(thoughtsDir, 'README.md');
  if (!fs.existsSync(readmePath)) {
    fs.writeFileSync(readmePath, `# Thoughts Directory (CCv3)

This directory is auto-created by \`ccv3-structure-check\` addon.

## Structure

- \`ledgers/\` - Continuity ledgers (legacy)
- \`shared/handoffs/\` - Session handoff documents
- \`shared/plans/\` - Implementation plans

## Usage

- Run \`/onboard\` to analyze codebase and create initial ledger
- Run \`/continuity_ledger\` to update session state
- Run \`/create_handoff\` before ending session
`);
  }

  const output: HookOutput = {
    result: 'continue',
    message: `\u2705 CCv3 structure created: ${created.join(', ')}. Run /onboard to initialize.`
  };

  console.log(JSON.stringify(output));
}

async function readStdin(): Promise<string> {
  return new Promise((resolve) => {
    let data = '';
    process.stdin.on('data', chunk => data += chunk);
    process.stdin.on('end', () => resolve(data));
  });
}

main().catch(err => {
  console.error('CCv3 structure check error:', err);
  // Don't block on errors
  console.log(JSON.stringify({ result: 'continue' }));
});
