# Nutrition Tracker — iOS

Полный порт Android-приложения "Питание от Андрюхи" на iOS (SwiftUI).

## Архитектура

- **UI**: SwiftUI (iOS 17+)
- **Архитектура**: MVVM + Repository
- **База данных**: SwiftData (аналог Room)
- **Сеть**: URLSession (async/await)
- **Камера**: AVFoundation (сканер штрих-кодов), UIImagePickerController (фото)

## Структура проекта

```
NutritionTracker/
├── NutritionTrackerApp.swift    — Точка входа
├── Models/
│   ├── NutrientData.swift       — Модель нутриентов (32 поля)
│   ├── FoodModels.swift         — FoodAnalysisResult, FoodIdentity, SupplementResult
│   └── NutrientTopFoods.swift   — Топ продуктов по нутриентам
├── Database/
│   ├── DatabaseModels.swift     — SwiftData модели (UserProfile, DailyNorms, FoodEntry, FoodCache)
│   └── DatabaseManager.swift    — CRUD операции
├── Services/
│   ├── APIConfig.swift          — Ключи API и конфигурация моделей
│   ├── APIModels.swift          — Модели запросов/ответов (OpenRouter, USDA, OFF)
│   ├── NetworkService.swift     — HTTP клиент
│   └── NutritionRepository.swift— Бизнес-логика (анализ еды, кэш, обогащение)
├── ViewModels/
│   └── MainViewModel.swift      — Состояние UI и действия
├── Views/
│   ├── Screens/
│   │   ├── MainScreen.swift
│   │   ├── OnboardingScreen.swift
│   │   ├── HistoryScreen.swift
│   │   ├── StatisticsScreen.swift
│   │   ├── EditProfileScreen.swift
│   │   ├── SavedProductsScreen.swift
│   │   ├── BarcodeScannerScreen.swift
│   │   └── PhotoCaptureScreen.swift
│   └── Components/
│       └── NutrientProgressView.swift
├── Utils/
│   └── Transliteration.swift
├── Config.plist                 — API ключи (не коммитить!)
└── Assets.xcassets/
```

## Настройка

1. Откройте `NutritionTracker.xcodeproj` в Xcode
2. В `Config.plist` замените `YOUR_OPENROUTER_API_KEY_HERE` на ваш ключ OpenRouter
3. Выберите устройство/симулятор и запустите (⌘R)

## API ключи

- **OpenRouter**: Платный, хранить в `Config.plist` (НЕ коммитить в git)
- **USDA FoodData Central**: Бесплатный, захардкожен
- **OpenFoodFacts**: Бесплатный, без ключа

## Функциональность (идентична Android)

- ✅ Ввод еды текстом (русский/украинский)
- ✅ Распознавание нутриентов через USDA + AI
- ✅ Сканирование штрих-кодов (AVFoundation)
- ✅ Фотографирование еды + AI анализ
- ✅ БАДы/витамины через штрих-код
- ✅ Персональные нормы через AI
- ✅ Прогресс-бары по 32 нутриентам
- ✅ Умное кэширование
- ✅ История за 14 дней
- ✅ Статистика
- ✅ Коррекция обогащения муки (US → Eastern Europe)
- ✅ Обогащение жиров (saturated/mono/poly)
