import { defineStore } from 'pinia'
import { api } from '../api'

export const useInbox = defineStore('inbox', {
  state: () => ({
    mailboxes: [],
    mailboxId: null,        // null = all mailboxes
    folder: 'unassigned',
    query: '',
    conversations: [],
    folderCounts: {},
    current: null,          // full conversation with messages
    viewers: [],
    unread: 0,
    loading: false,
  }),
  actions: {
    async loadMailboxes() {
      this.mailboxes = await api.get('/api/mailboxes')
      if (this.mailboxId && !this.mailboxes.some(m => m.id === this.mailboxId)) this.mailboxId = null
    },
    async loadConversations() {
      this.loading = true
      try {
        const params = new URLSearchParams({ folder: this.folder })
        if (this.mailboxId) params.set('mailbox_id', this.mailboxId)
        if (this.query) params.set('q', this.query)
        const data = await api.get(`/api/conversations?${params}`)
        this.conversations = data.conversations
        this.folderCounts = data.folder_counts
      } finally {
        this.loading = false
      }
    },
    async open(id) {
      if (this.current?.id !== id) { this.current = null; this.viewers = [] }
      const data = await api.get(`/api/conversations/${id}`)
      this.current = data
      this.viewers = data.viewers || []
    },
    async update(id, attrs) {
      const data = await api.patch(`/api/conversations/${id}`, attrs)
      if (this.current?.id === id) this.current = data
      await this.loadConversations()
    },
    async refreshUnread() {
      const data = await api.get('/api/notifications')
      this.unread = data.unread
    },
  },
})
