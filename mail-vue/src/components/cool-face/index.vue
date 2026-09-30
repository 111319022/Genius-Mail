<template>
  <svg class="cool-face" viewBox="0 0 64 64" :width="size" :height="size" aria-hidden="true">
    <circle cx="32" cy="32" r="30" fill="#FFC107"/>
    <template v-if="variant === 'cool'">
      <path d="M8 24h21v4a10 10 0 0 1-10 10h-1a10 10 0 0 1-10-10z" fill="#212529"/>
      <path d="M56 24H35v4a10 10 0 0 0 10 10h1a10 10 0 0 0 10-10z" fill="#212529"/>
      <rect x="28" y="24" width="8" height="3" fill="#212529"/>
      <path d="M14 27h4l-4.5 6h-3.2z" fill="#fff" fill-opacity=".28"/>
      <path d="M42 27h4l-4.5 6h-3.2z" fill="#fff" fill-opacity=".28"/>
      <path d="M21 45c4 6.5 16 6.5 22 0" fill="none" stroke="#212529" stroke-width="3" stroke-linecap="round"/>
    </template>
    <template v-else-if="variant === 'grin'">
      <ellipse cx="22" cy="24" rx="3.2" ry="4.5" fill="#212529"/>
      <ellipse cx="42" cy="24" rx="3.2" ry="4.5" fill="#212529"/>
      <path d="M15 37h34a17 15 0 0 1-34 0z" fill="#212529"/>
      <path d="M18.5 37h27v4.5h-27z" fill="#fff"/>
    </template>
    <template v-else-if="variant === 'wink'">
      <ellipse cx="22" cy="25" rx="3.2" ry="4.5" fill="#212529"/>
      <path d="M36 26c2.5-4.5 8.5-4.5 11 0" fill="none" stroke="#212529" stroke-width="3" stroke-linecap="round"/>
      <path d="M19 40c5 8 21 8 26 0" fill="none" stroke="#212529" stroke-width="3" stroke-linecap="round"/>
    </template>
    <template v-else-if="variant === 'heart'">
      <path d="M22 34c-8-5-9-9-6.500-12 2.500-2.500 5.500-.5 6.500 2 1-2.500 4-4.500 6.500-2 2.500 3 1.500 7-6.500 12z" fill="#DC3545"/>
      <path d="M42 34c-8-5-9-9-6.500-12 2.500-2.500 5.500-.5 6.500 2 1-2.500 4-4.500 6.500-2 2.500 3 1.500 7-6.500 12z" fill="#DC3545"/>
      <path d="M20 42c5 9 19 9 24 0z" fill="#212529"/>
    </template>
    <template v-else-if="variant === 'tongue'">
      <path d="M14 24l10 3M50 24l-10 3" fill="none" stroke="#212529" stroke-width="3" stroke-linecap="round"/>
      <path d="M19 40c5 6 21 6 26 0" fill="none" stroke="#212529" stroke-width="3" stroke-linecap="round"/>
      <path d="M26 45h12v5a6 6 0 0 1-12 0z" fill="#F28B9B"/>
      <path d="M32 46v6" stroke="#DC3545" stroke-width="1.500" stroke-linecap="round" stroke-opacity=".5"/>
    </template>
  </svg>
</template>

<script setup>
defineProps({
  size: {
    type: [Number, String],
    default: 32
  },
  variant: {
    type: String,
    default: 'cool'
  }
})
</script>

<style scoped>
.cool-face {
  display: block;
  flex-shrink: 0;
}
</style>
