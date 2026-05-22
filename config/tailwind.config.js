/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./app/views/**/*.erb', './lib/**/*.rb'],
  darkMode: 'class',
  theme: {
    extend: {
      maxWidth: {
        prose: '70ch',
      },
      fontFamily: {
        sans: ['Inter', 'ui-sans-serif', 'system-ui', '-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'Helvetica', 'Arial', 'sans-serif'],
        serif: ['Newsreader', 'ui-serif', 'Georgia', 'Cambria', 'Times New Roman', 'serif'],
        mono: ['ui-monospace', 'SFMono-Regular', 'Menlo', 'Consolas', 'monospace'],
      },
      colors: {
        paper: 'rgb(var(--paper) / <alpha-value>)',
        ink: 'rgb(var(--ink) / <alpha-value>)',
        faint: 'rgb(var(--faint) / <alpha-value>)',
        rule: 'rgb(var(--rule) / <alpha-value>)',
        tag: 'rgb(var(--tag) / <alpha-value>)',
        accent: 'rgb(var(--accent) / <alpha-value>)',
        good: 'rgb(var(--good) / <alpha-value>)',
        bad: 'rgb(var(--bad) / <alpha-value>)',
        'cell-1': 'rgb(var(--cell-1) / <alpha-value>)',
        'cell-2': 'rgb(var(--cell-2) / <alpha-value>)',
        'cell-3': 'rgb(var(--cell-3) / <alpha-value>)',
      },
    },
  },
  plugins: [],
};
