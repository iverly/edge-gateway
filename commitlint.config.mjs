// Commit scopes. The repository is small enough for a fixed list; a new area adds its scope here
// in the commit that creates it.
const scopes = [
  'gateway', // rootfs/usr/local/bin/edge-gateway. Example: "feat(gateway): render the hysteria2 lane"
  'watch', // rootfs/usr/local/bin/edge-watch. Example: "feat(watch): probe the peers"
  'image', // Dockerfile, .dockerignore. Example: "chore(image): bump sing-box to v1.14.5"
  'compose', // docker-compose.yml, .env.example. Example: "feat(compose): mount the data volume"
  'test', // tests/. Example: "test(test): reach the internet through each lane"
  'ci', // .github/workflows. Example: "ci(ci): publish the arm64 image"
  'agents-md', // AGENTS.md. Example: "docs(agents-md): document the commit scopes"
  'docs', // README.md and other documentation. Example: "docs(docs): describe the lanes"
  'git', // .gitignore, .gitattributes. Example: "chore(git): ignore the data folder"
  'hooks', // lefthook.yml, scripts/install-hooks.sh. Example: "chore(hooks): lint shell scripts on commit"
  'deps', // dependency bumps. Example: "chore(deps): bump lefthook to 2.3"
  'release', // release tooling and changelog. Example: "chore(release): v0.1.0"
  'repo', // the repository as a whole (its first commit, cross-cutting files)
  'tooling', // package.json, editor and formatter configuration
];

export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'scope-enum': [2, 'always', scopes],
    'scope-empty': [2, 'never'],
    'body-max-line-length': [0, 'always', 100],
  },
};
