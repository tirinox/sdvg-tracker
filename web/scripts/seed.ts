// Fills (or clears) the demo data on a sync server, using the same code as the web app.
//   npx tsx scripts/seed.ts --url http://localhost:8420 [--clear]   (token in SDVG_TOKEN)
import 'fake-indexeddb/auto'
import { Store } from '../src/db/store'
import { clearDemo, generateDemo } from '../src/demo/demo'
import { localNow, logicalDay } from '../src/domain/dates'
import { SyncClient, saveSyncConfig } from '../src/sync/client'

const args = process.argv.slice(2)
const url = args[args.indexOf('--url') + 1]
const token = process.env.SDVG_TOKEN
if (!args.includes('--url') || !url || !token) {
  console.error('usage: SDVG_TOKEN=... tsx scripts/seed.ts --url http://host:port [--clear]')
  process.exit(2)
}

const store = await Store.open(`seed-${crypto.randomUUID()}`)
await saveSyncConfig(store, { baseUrl: url.replace(/\/$/, ''), token })
const client = new SyncClient(store)

async function sync(step: string) {
  await client.sync()
  if (client.status.state !== 'idle') {
    console.error(`${step}: sync failed: ${client.status.state} ${client.status.error ?? ''}`)
    process.exit(1)
  }
}

// Pull first: clearing needs to see what is there, and seeding merges into it.
await sync('pull')
const settings = await store.settings()
const now = localNow()
const today = logicalDay(now, settings.day_start_hour)

if (args.includes('--clear')) {
  const n = await clearDemo(store)
  await sync('push')
  console.log(`Demo data cleared (${n} changes).`)
} else {
  await generateDemo(store, today, now)
  const queued = await store.db.outbox.count()
  await sync('push')
  console.log(`Demo data for ${today} pushed (${queued} changes).`)
}
store.close()
