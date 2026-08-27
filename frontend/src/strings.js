// UI strings per locale (H16). `t` is reactive: setLocale swaps the language live.
import { reactive } from 'vue'

const en = {
  appName: 'Flow',
  login: 'Log in', logout: 'Log out', email: 'Email', password: 'Password',
  loginFailed: 'Wrong email or password',
  folders: {
    unassigned: 'Unassigned', mine: 'Mine', assigned: 'Assigned',
    snoozed: 'Snoozed', drafts: 'Drafts', closed: 'Closed', spam: 'Spam', trash: 'Trash',
  },
  statuses: { active: 'Active', pending: 'Pending', closed: 'Closed', spam: 'Spam', trash: 'Trash' },
  reply: 'Reply', note: 'Note', send: 'Send', sendAndClose: 'Send & close', saveNote: 'Add note',
  assignTo: 'Assign', unassigned: 'Unassigned', noConversations: 'No conversations here',
  search: 'Search…', newConversation: 'New conversation', settings: 'Settings',
  viewing: 'is viewing', savedReplies: 'Saved replies', tags: 'Tags',
  to: 'To', cc: 'Cc', subject: 'Subject', save: 'Save', cancel: 'Cancel', delete: 'Delete',
  draftSaved: 'Draft saved', internalNote: 'Internal note — not emailed',
  bounced: 'Bounced', queued: 'Queued', failed: 'Failed to send',
  follow: 'Follow', following: '✓ Following', customer: 'Customer', onThisThread: 'On this thread',
  insights: 'Insights', myFolders: 'My folders', newFolder: 'New folder',
  previousConversations: 'Previous conversations', mergeCustomer: 'Merge another address…',
  edit: 'Edit', company: 'Company', phone: 'Phone', notes: 'Notes',
}

const da = {
  appName: 'Flow',
  login: 'Log ind', logout: 'Log ud', email: 'E-mail', password: 'Adgangskode',
  loginFailed: 'Forkert e-mail eller adgangskode',
  folders: {
    unassigned: 'Ufordelte', mine: 'Mine', assigned: 'Tildelte',
    snoozed: 'Udsatte', drafts: 'Kladder', closed: 'Lukkede', spam: 'Spam', trash: 'Papirkurv',
  },
  statuses: { active: 'Aktiv', pending: 'Afventer', closed: 'Lukket', spam: 'Spam', trash: 'Papirkurv' },
  reply: 'Svar', note: 'Note', send: 'Send', sendAndClose: 'Send og luk', saveNote: 'Tilføj note',
  assignTo: 'Tildel', unassigned: 'Ufordelt', noConversations: 'Ingen samtaler her',
  search: 'Søg…', newConversation: 'Ny samtale', settings: 'Indstillinger',
  viewing: 'kigger med', savedReplies: 'Standardsvar', tags: 'Tags',
  to: 'Til', cc: 'Cc', subject: 'Emne', save: 'Gem', cancel: 'Annullér', delete: 'Slet',
  draftSaved: 'Kladde gemt', internalNote: 'Intern note — sendes ikke',
  bounced: 'Afvist', queued: 'I kø', failed: 'Afsendelse fejlede',
  follow: 'Følg', following: '✓ Følger', customer: 'Kunde', onThisThread: 'På denne tråd',
  insights: 'Indsigt', myFolders: 'Mine mapper', newFolder: 'Ny mappe',
  previousConversations: 'Tidligere samtaler', mergeCustomer: 'Flet anden adresse…',
  edit: 'Redigér', company: 'Firma', phone: 'Telefon', notes: 'Noter',
}

export const locales = { en, da }
export const t = reactive(JSON.parse(JSON.stringify(en)))

export function setLocale(code) {
  Object.assign(t, JSON.parse(JSON.stringify(locales[code] || en)))
}
