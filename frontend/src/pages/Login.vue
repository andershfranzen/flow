<script setup>
import { ref, computed, onMounted, nextTick } from 'vue'
import { useRouter } from 'vue-router'
import { useSession } from '../stores/session'
import { t } from '../strings'
import { Eye, EyeOff, Github } from 'lucide-vue-next'

const showPassword = ref(false)

const session = useSession()
const router = useRouter()
const email = ref('')
const password = ref('')
const error = ref(new URLSearchParams(window.location.search).get('sso_error') || '')
const busy = ref(false)
const otpNeeded = ref(false)
const otpCode = ref('')

// SSO on → Microsoft-only; the password form only exists when it's usable.
const ssoOnly = computed(() => session.sso?.enabled && !session.sso?.password_login)

onMounted(() => nextTick(() => document.querySelector('#email')?.focus()))

async function submit() {
  busy.value = true
  error.value = ''
  try {
    await session.login(email.value, password.value, otpNeeded.value ? otpCode.value : undefined)
    router.push('/inbox')
  } catch (e) {
    if (e.otpRequired || e.message === 'otp_required') {
      otpNeeded.value = true
      error.value = otpCode.value ? 'Wrong code' : ''
    } else {
      error.value = t.loginFailed
    }
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <main class="login-wrap">
    <div class="login-waves" aria-hidden="true">
      <svg class="wave wave-a" viewBox="0 0 1440 320" preserveAspectRatio="none">
        <path d="M0,192 C240,120 420,260 720,208 C1020,156 1200,60 1440,128 L1440,320 L0,320 Z" />
      </svg>
      <svg class="wave wave-b" viewBox="0 0 1440 320" preserveAspectRatio="none">
        <path d="M0,240 C280,160 520,290 820,236 C1120,182 1260,120 1440,180 L1440,320 L0,320 Z" />
      </svg>
      <svg class="wave wave-c" viewBox="0 0 1440 320" preserveAspectRatio="none">
        <path d="M0,280 C320,220 560,310 880,268 C1200,226 1320,190 1440,232 L1440,320 L0,320 Z" />
      </svg>
    </div>
    <form class="login-card" @submit.prevent="submit">
      <div class="login-brand">
        <template v-if="session.org?.logo_url">
          <img class="company-logo" :src="session.org.logo_url" :alt="session.org.site_name || 'Company logo'" draggable="false" />
          <div class="brand by-flow">by {{ t.appName }}</div>
        </template>
        <h1 v-else class="brand-h1">{{ t.appName }}</h1>
      </div>
      <template v-if="ssoOnly">
        <a class="ms-signin" href="/auth/microsoft/start">
          <svg width="17" height="17" viewBox="0 0 21 21" aria-hidden="true">
            <rect x="0" y="0" width="10" height="10" fill="#f25022" /><rect x="11" y="0" width="10" height="10" fill="#7fba00" />
            <rect x="0" y="11" width="10" height="10" fill="#00a4ef" /><rect x="11" y="11" width="10" height="10" fill="#ffb900" />
          </svg>
          Sign in with Microsoft
        </a>
        <p v-if="error" class="error-text">{{ error }}</p>
      </template>
      <template v-else>
        <div>
          <label for="email">{{ t.email }}</label>
          <input id="email" name="email" v-model="email" type="email" autocomplete="username"
                 autocapitalize="none" spellcheck="false" required autofocus style="width:100%" />
        </div>
        <div>
          <label for="password">{{ t.password }}</label>
          <div class="password-field">
            <input id="password" name="password" v-model="password" :type="showPassword ? 'text' : 'password'"
                   autocomplete="current-password" required />
            <button type="button" class="ghost reveal" :data-tip="showPassword ? 'Hide password' : 'Show password'"
                    :aria-label="showPassword ? 'Hide password' : 'Show password'"
                    @click="showPassword = !showPassword">
              <component :is="showPassword ? EyeOff : Eye" :size="16" />
            </button>
          </div>
        </div>
        <div v-if="otpNeeded">
          <label for="otp">Authenticator code</label>
          <input id="otp" name="otp" v-model="otpCode" inputmode="numeric" autocomplete="one-time-code"
                 required style="width:100%" />
        </div>
        <p v-if="error" class="error-text" role="alert">{{ error }}</p>
        <button class="primary" :disabled="busy">{{ t.login }}</button>
      </template>
    </form>
    <a class="open-source" href="https://github.com/andershfranzen/flow" target="_blank" rel="noopener">
      <Github :size="15" /> Open-source, always.
    </a>
  </main>
</template>
