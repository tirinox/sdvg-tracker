import 'fake-indexeddb/auto'
import { setLangPref } from '../app/i18n'

// Tests check the Russian strings, whatever the machine's language.
setLangPref('ru')
