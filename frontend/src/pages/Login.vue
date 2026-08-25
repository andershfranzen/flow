<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useSession } from '../stores/session'
import { t } from '../strings'

const session = useSession()
const router = useRouter()
const email = ref('')
const password = ref('')
const error = ref('')
const busy = ref(false)
const otpNeeded = ref(false)
const otpCode = ref('')

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
    <form class="login-card" @submit.prevent="submit">
      <h1>{{ t.appName }}</h1>
      <div>
        <label for="email">{{ t.email }}</label>
        <input id="email" v-model="email" type="email" autocomplete="username" required style="width:100%" />
      </div>
      <div>
        <label for="password">{{ t.password }}</label>
        <input id="password" v-model="password" type="password" autocomplete="current-password" required style="width:100%" />
      </div>
      <div v-if="otpNeeded">
        <label for="otp">Authenticator code</label>
        <input id="otp" v-model="otpCode" inputmode="numeric" autocomplete="one-time-code" required style="width:100%" />
      </div>
      <p v-if="error" class="error-text">{{ error }}</p>
      <button class="primary" :disabled="busy">{{ t.login }}</button>
    </form>
  </main>
</template>
