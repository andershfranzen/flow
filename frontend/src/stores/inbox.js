import { defineStore } from 'pinia'
import { api } from '../api'

export const useInbox = defineStore('inbox', {
  state: () => ({
    mailboxes: [],
    personalFolders: [],
    personalFolderId: null, // viewing a personal folder
    mailboxId: null,        // null = all mailboxes
    folder: 'unassigned',
    query: '',
    sort: 'newest',
    assigneeFilter: '',
    tagFilter: '',
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
    async loadPersonalFolders() {
      this.personalFolders = await api.get('/api/personal_folders')
    },
    async loadConversations() {
      this._seq = (this._seq || 0) + 1
      const seq = this._seq
      this.loading = true
      try {
        const params = new URLSearchParams({ folder: this.folder })
        if (this.personalFolderId) params.set('personal_folder_id', this.personalFolderId)
        if (this.mailboxId) params.set('mailbox_id', this.mailboxId)
        if (this.query) params.set('q', this.query)
        if (this.sort === 'oldest') params.set('sort', 'oldest')
        if (this.assigneeFilter) params.set('assignee_id', this.assigneeFilter)
        if (this.tagFilter) params.set('tag', this.tagFilter)
        const data = await api.get(`/api/conversations?${params}`)
        if (seq !== this._seq) return // a newer keystroke superseded this request
        this.conversations = data.conversations
        this.folderCounts = data.folder_counts
      } catch (e) {
        // The personal folder vanished (deleted in another tab): self-heal.
        if (e.status === 404 && this.personalFolderId) {
          this.personalFolderId = null
          this.folder = 'unassigned'
          this.loadPersonalFolders()
          return this.loadConversations()
        }
        throw e
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
