import { expect, mock, test } from 'claude-code/testing'
import { BASH_NOTE, NOTE } from '../hooks/register.ts'

const ENGINE = { plugin: 'engine', tier: 'core' } as const
const READ = 'Reads a file from the local filesystem.'

type Entry = { name: string; kind: 'file' | 'dir' }
type World = {
  tree: Record<string, readonly Entry[]>
  env?: Record<string, string>
  existing?: readonly string[]
  installed?: 'swift-sure' | 'sift' | 'none'
  runFails?: boolean
}

// Stands the engine beneath the mod: the file system, environment and processes the world describes,
// then fires session.start in `cwd` and describes `tool`, answering with the engine's own text.
async function describe($: any, on: any, world: World, cwd: string, tool = 'Read'): Promise<string> {
  mock.env(on, world.env ?? { HOME: '/home/someone' })
  on('fs.list', (_: unknown, e: { path: string }) => {
    const entries = world.tree[e.path]
    if (entries === undefined) return { deny: 'ENOENT' }
    return { value: entries.map(x => ({ ...x, size: 0, mtimeMs: 0, isLink: false })) }
  })
  on('fs.exists', (_: unknown, e: { path: string }) => ({ value: (world.existing ?? []).includes(e.path) }))
  on('process.run', (_: unknown, e: { argv: readonly string[] }) => {
    if (world.runFails) return { deny: 'cannot start' }
    expect(e.argv[0]).toBe('which')
    const onPath = world.installed ?? 'swift-sure'
    const found = e.argv[1] === onPath
    return { value: { exitCode: found ? 0 : 1, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('session.start', () => ({ cwd }))
  on('tool.describe', (_: unknown, e: { description: string }) => ({ description: e.description }))
  await $.session.start({ cwd, surface: null, isInteractive: false })
  const answer = await $.tool.describe({ tool, description: READ, provider: ENGINE })
  return answer.description
}

const SWIFT_PACKAGE: World['tree'] = {
  '/work/pkg': [
    { name: 'Package.swift', kind: 'file' },
    { name: 'Sources', kind: 'dir' },
  ],
  '/work': [{ name: 'pkg', kind: 'dir' }],
  '/': [{ name: 'work', kind: 'dir' }],
}

test('a Swift package with swift-sure on PATH: Read gains the paragraph', async ($, on) => {
  expect(await describe($, on, { tree: SWIFT_PACKAGE }, '/work/pkg')).toBe(`${READ}\n\n${NOTE}`)
})

test('the paragraph stays within 60 words', () => {
  expect(NOTE.split(/\s+/).length <= 60).toBe(true)
})

test('an ancestor Package.swift counts, and Grep and Glob gain it too', async ($, on) => {
  const tree = { ...SWIFT_PACKAGE, '/work/pkg/Sources': [{ name: 'Core', kind: 'dir' as const }] }
  expect(await describe($, on, { tree }, '/work/pkg/Sources', 'Grep')).toBe(`${READ}\n\n${NOTE}`)
})

test('a .swift file at depth 2 counts', async ($, on) => {
  const tree = {
    '/work/app': [{ name: 'App', kind: 'dir' as const }],
    '/work/app/App': [{ name: 'Main.swift', kind: 'file' as const }],
    '/work': [],
    '/': [],
  }
  expect(await describe($, on, { tree }, '/work/app', 'Glob')).toBe(`${READ}\n\n${NOTE}`)
})

test('a repository with no Swift in it: untouched', async ($, on) => {
  const tree = {
    '/work/web': [
      { name: 'package.json', kind: 'file' as const },
      { name: 'src', kind: 'dir' as const },
    ],
    '/work/web/src': [{ name: 'index.ts', kind: 'file' as const }],
    '/work': [],
    '/': [],
  }
  expect(await describe($, on, { tree }, '/work/web')).toBe(READ)
})

test('neither swift-sure nor sift on PATH: untouched', async ($, on) => {
  expect(await describe($, on, { tree: SWIFT_PACKAGE, installed: 'none' as const }, '/work/pkg')).toBe(READ)
})

test('SWIFT_SURE_MOD=off: untouched', async ($, on) => {
  const env = { HOME: '/home/someone', SWIFT_SURE_MOD: 'off' }
  expect(await describe($, on, { tree: SWIFT_PACKAGE, env }, '/work/pkg')).toBe(READ)
})

test('a mod-off file in SWIFT_SURE_HOME: untouched', async ($, on) => {
  const env = { HOME: '/home/someone', SWIFT_SURE_HOME: '/scratch/swift-sure' }
  const world = { tree: SWIFT_PACKAGE, env, existing: ['/scratch/swift-sure/mod-off'] }
  expect(await describe($, on, world, '/work/pkg')).toBe(READ)
})

test('a mod-off file in ~/.swift-sure: untouched', async ($, on) => {
  const world = { tree: SWIFT_PACKAGE, existing: ['/home/someone/.swift-sure/mod-off'] }
  expect(await describe($, on, world, '/work/pkg')).toBe(READ)
})

test('the alias sift alone on PATH: Read gains the paragraph', async ($, on) => {
  const world = { tree: SWIFT_PACKAGE, installed: 'sift' as const }
  expect(await describe($, on, world, '/work/pkg')).toBe(`${READ}\n\n${NOTE}`)
})

test('the legacy SIFT_MOD=off still switches it off', async ($, on) => {
  const env = { HOME: '/home/someone', SIFT_MOD: 'off' }
  expect(await describe($, on, { tree: SWIFT_PACKAGE, env }, '/work/pkg')).toBe(READ)
})

test('a mod-off file in the legacy SIFT_HOME: untouched', async ($, on) => {
  const env = { HOME: '/home/someone', SIFT_HOME: '/scratch/sift' }
  const world = { tree: SWIFT_PACKAGE, env, existing: ['/scratch/sift/mod-off'] }
  expect(await describe($, on, world, '/work/pkg')).toBe(READ)
})

test('a mod-off file in ~/.sift: untouched', async ($, on) => {
  const world = { tree: SWIFT_PACKAGE, existing: ['/home/someone/.sift/mod-off'] }
  expect(await describe($, on, world, '/work/pkg')).toBe(READ)
})

test('a call that throws (the process cannot start): untouched', async ($, on) => {
  expect(await describe($, on, { tree: SWIFT_PACKAGE, runFails: true }, '/work/pkg')).toBe(READ)
})

test('a tool other than Read, Grep, Glob or Bash: untouched', async ($, on) => {
  expect(await describe($, on, { tree: SWIFT_PACKAGE }, '/work/pkg', 'Edit')).toBe(READ)
})

test('a describe before session.start: untouched', async ($, on) => {
  on('tool.describe', (_: unknown, e: { description: string }) => ({ description: e.description }))
  const answer = await $.tool.describe({ tool: 'Read', description: READ, provider: ENGINE })
  expect(answer.description).toBe(READ)
})

const BASH_ON = { HOME: '/home/someone', SWIFT_SURE_MOD_BASH: 'on' }

test('SWIFT_SURE_MOD_BASH unset: Bash untouched in a Swift repo', async ($, on) => {
  expect(await describe($, on, { tree: SWIFT_PACKAGE }, '/work/pkg', 'Bash')).toBe(READ)
})

test('SWIFT_SURE_MOD_BASH=on in a Swift repo: Bash gains its own paragraph, Read is unchanged', async ($, on) => {
  const world = { tree: SWIFT_PACKAGE, env: BASH_ON }
  expect(await describe($, on, world, '/work/pkg', 'Bash')).toBe(`${READ}\n\n${BASH_NOTE}`)
})

test('SWIFT_SURE_MOD_BASH=on: Read still gets only the Read paragraph', async ($, on) => {
  expect(await describe($, on, { tree: SWIFT_PACKAGE, env: BASH_ON }, '/work/pkg')).toBe(`${READ}\n\n${NOTE}`)
})

test('the Bash paragraph stays within 40 words', () => {
  expect(BASH_NOTE.split(/\s+/).length <= 40).toBe(true)
})

test('SWIFT_SURE_MOD_BASH=on, no Swift in the repository: Bash untouched', async ($, on) => {
  const tree = { '/work/web': [{ name: 'package.json', kind: 'file' as const }], '/work': [], '/': [] }
  expect(await describe($, on, { tree, env: BASH_ON }, '/work/web', 'Bash')).toBe(READ)
})

test('SWIFT_SURE_MOD_BASH=on, no binary on PATH: Bash untouched', async ($, on) => {
  const world = { tree: SWIFT_PACKAGE, env: BASH_ON, installed: 'none' as const }
  expect(await describe($, on, world, '/work/pkg', 'Bash')).toBe(READ)
})

test('SWIFT_SURE_MOD_BASH=on with SWIFT_SURE_MOD=off: Bash untouched', async ($, on) => {
  const env = { ...BASH_ON, SWIFT_SURE_MOD: 'off' }
  expect(await describe($, on, { tree: SWIFT_PACKAGE, env }, '/work/pkg', 'Bash')).toBe(READ)
})

test('SWIFT_SURE_MOD_BASH=on, a call that throws: Bash untouched', async ($, on) => {
  const world = { tree: SWIFT_PACKAGE, env: BASH_ON, runFails: true }
  expect(await describe($, on, world, '/work/pkg', 'Bash')).toBe(READ)
})

test('the legacy SIFT_MOD_BASH=on still gives Bash its paragraph', async ($, on) => {
  const env = { HOME: '/home/someone', SIFT_MOD_BASH: 'on' }
  expect(await describe($, on, { tree: SWIFT_PACKAGE, env }, '/work/pkg', 'Bash')).toBe(`${READ}\n\n${BASH_NOTE}`)
})
