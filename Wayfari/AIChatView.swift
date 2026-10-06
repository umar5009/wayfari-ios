import SwiftUI

// MARK: - Chat ViewModel
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages:  [ChatMessage]   = []
    @Published var options:   [String]        = []
    @Published var packages:  [TravelPackage] = []
    @Published var tourPlan:  TourPlan?       = nil
    @Published var isTyping   = false
    @Published var inputText  = ""

    private enum Step { case country, budget, clarifyingTour, done }
    private var step: Step = .country
    private var selectedCountry = ""
    private var selectedBudget  = ""
    /// In-progress tour details while we ask for missing destination / days.
    private var draftTour = TourRequest.empty
    /// Last completed request so follow-ups like “5 people” can refresh the plan.
    private var lastTourRequest: TourRequest?

    // MARK: - All countries
    let countryOpts: [String] = [
        // Middle East & Gulf
        "🇦🇪 UAE / Dubai", "🇸🇦 Saudi Arabia", "🇦🇿 Azerbaijan",
        "🇲🇻 Maldives", "🇴🇲 Oman", "🇶🇦 Qatar", "🇧🇭 Bahrain", "🇰🇼 Kuwait",
        // South Asia
        "🇵🇰 Pakistan", "🇮🇳 India", "🇱🇰 Sri Lanka", "🇧🇩 Bangladesh", "🇳🇵 Nepal",
        // Southeast & East Asia
        "🇲🇾 Malaysia", "🇨🇳 China", "🇯🇵 Japan", "🇰🇷 South Korea",
        "🇹🇭 Thailand", "🇸🇬 Singapore", "🇮🇩 Indonesia", "🇻🇳 Vietnam",
        // Schengen Zone
        "🇩🇪 Germany", "🇫🇷 France", "🇮🇹 Italy", "🇪🇸 Spain",
        "🇳🇱 Netherlands", "🇧🇪 Belgium", "🇦🇹 Austria", "🇨🇭 Switzerland",
        "🇵🇹 Portugal", "🇬🇷 Greece", "🇸🇪 Sweden", "🇳🇴 Norway",
        "🇩🇰 Denmark", "🇫🇮 Finland", "🇨🇿 Czech Republic", "🇵🇱 Poland",
        "🇭🇺 Hungary", "🇸🇰 Slovakia", "🇸🇮 Slovenia", "🇭🇷 Croatia",
        "🇷🇴 Romania", "🇧🇬 Bulgaria", "🇱🇺 Luxembourg", "🇲🇹 Malta",
        "🇮🇸 Iceland", "🇱🇮 Liechtenstein", "🇪🇪 Estonia", "🇱🇻 Latvia", "🇱🇹 Lithuania",
        // Non-Schengen Europe
        "🇬🇧 United Kingdom", "🇮🇪 Ireland", "🇹🇷 Turkey",
        "🇷🇸 Serbia", "🇲🇰 North Macedonia", "🇦🇱 Albania",
        "🇲🇪 Montenegro", "🇧🇦 Bosnia & Herzegovina", "🇺🇦 Ukraine", "🇬🇪 Georgia",
        // Americas
        "🇺🇸 United States", "🇨🇦 Canada", "🇲🇽 Mexico",
        "🇧🇷 Brazil", "🇦🇷 Argentina", "🇨🇴 Colombia", "🇵🇪 Peru", "🇨🇱 Chile",
        // Oceania
        "🇦🇺 Australia", "🇳🇿 New Zealand", "🇫🇯 Fiji",
        // Africa
        "🇿🇦 South Africa", "🇰🇪 Kenya", "🇲🇦 Morocco", "🇪🇬 Egypt", "🇹🇿 Tanzania",
    ]

    let budgetOpts = ["$500 – $1,000", "$1,000 – $2,000", "$2,000 – $4,000", "$4,000+"]

    // MARK: - Q&A knowledge bank
    private let qaBank: [(keywords: [String], reply: String)] = [
        (["visa", "entry", "permit", "passport", "document"],
         "Visa requirements depend on your passport. For UAE & Turkey, many nationalities get visa on arrival or eVisa. Schengen visas require a formal application with an appointment. Check iVisa.com for real-time requirements. 🛂"),
        (["weather", "climate", "temperature", "hot", "cold", "rain", "season", "best time", "when to go", "month"],
         "Best travel seasons vary by region: Dubai & Gulf → Oct–Apr. European Schengen → Jun–Sep. South Asia → Nov–Feb. Southeast Asia → Nov–Mar. Would you like a specific month recommendation? 🌤"),
        (["hotel", "stay", "accommodation", "hostel", "resort", "airbnb", "riad", "lodge"],
         "The packages above include curated hotels for every budget. Iconic picks: Burj Al Arab (Dubai), Ritz Paris (France), Baur au Lac (Zurich). Want me to compare the hotel tiers in more detail? 🏨"),
        (["flight", "fly", "airline", "ticket", "cheap", "airfare", "direct", "layover"],
         "For the best deals, book 6–8 weeks in advance. Emirates, Turkish Airlines and Qatar Airways offer excellent connections from South Asia to Europe and beyond. Skyscanner and Google Flights are great for comparison. ✈️"),
        (["food", "eat", "restaurant", "cuisine", "halal", "local", "street food", "dining"],
         "Halal food is widely available in UAE, Turkey, Malaysia and Morocco. In Europe, HalalTrip and Zabihah directories list certified restaurants. France, Germany and the UK have excellent halal dining scenes. 🍽️"),
        (["transport", "train", "bus", "taxi", "metro", "car", "uber", "careem", "travel around", "get around"],
         "Europe has superb rail networks — a Eurail Pass covers 33 countries. In UAE, Dubai Metro is cheap and fast. For South Asia intercity travel, trains are scenic and affordable. Uber/Careem work in most major cities. 🚆"),
        (["budget", "cheap", "afford", "expensive", "cost", "price", "spend", "money", "save"],
         "Smart budgeting tip: flights + hotel typically take 60–70% of your budget. Allocate 15–20% for food and 10–15% for local transport & activities. Travelling shoulder season (just before/after peak) saves 20–30%. 💰"),
        (["safe", "safety", "crime", "dangerous", "secure", "risk"],
         "Most popular tourist destinations are safe. UAE & Singapore rank among the world's safest countries. Standard city precautions apply in Europe. Always check your government's travel advisory 2 weeks before departure. 🛡️"),
        (["currency", "money", "exchange", "dollar", "euro", "dirham", "pound", "cash", "atm", "bank"],
         "UAE uses AED (pegged to USD). Most of Schengen uses Euro (€), except Switzerland (CHF), Norway (NOK), Sweden (SEK) and Denmark (DKK). UK uses GBP (£). Wise or Revolut cards give excellent exchange rates with no hidden fees. 💱"),
        (["package", "deal", "tour", "itinerary", "days", "nights", "how long", "duration"],
         "Tell me your destination and how many days you want — I’ll build a full day-by-day plan for exactly that length, with flights, hotels, and ticket prices. 🗺️"),
        (["schengen", "europe", "european", "visa free", "eu"],
         "The Schengen Area covers 29 countries with a single visa. Your Schengen visa lets you travel freely within all member states for up to 90 days in any 180-day period. Apply at the embassy of your primary destination. 🇪🇺"),
        (["recommend", "suggest", "advice", "tip", "best", "top"],
         "My top travel tips: 1) Book flights early for the best prices 2) Get travel insurance (mandatory for Schengen) 3) Download offline Google Maps 4) Keep digital passport copies 5) Inform your bank before travelling. 🌟"),
        (["insurance", "cover", "coverage", "medical", "emergency"],
         "Travel insurance is mandatory for Schengen visa applications. Look for policies covering medical (min €30,000), trip cancellation, and baggage loss. Trusted providers: World Nomads, AXA, and Allianz. 🏥"),
        (["hello", "hi", "hey", "help", "start", "plan", "trip", "travel", "going"],
         "Hi there! I'm here to help plan your perfect trip ✈️ Tell me where you want to go and for how many days — or ask about visas, weather, flights, and more."),
        (["thank", "thanks", "great", "awesome", "perfect", "nice", "good", "excellent", "brilliant"],
         "You're very welcome! Happy to help make your trip unforgettable. Is there anything else you'd like to know before you book? 😊"),
        (["hotel rating", "star", "3 star", "4 star", "5 star", "luxury", "comfort"],
         "Our packages cover 3 tiers: 5-Star Luxury (iconic flagship hotels, butler service), 4-Star Comfort (premium location & amenities), 3-Star Budget (clean, central, great value). Tap any package card above to expand the full breakdown! 🏨"),
        (["cancel", "refund", "change", "flexible"],
         "Always book refundable or flexible-rate rooms when possible — usually 10–15% more but worth it for peace of mind. For flights, look for 'Flex' or 'Changeable' fares on Emirates, Turkish Airlines, and Qatar Airways. 📋"),
    ]

    init() { startFlow() }

    func restart() {
        messages = []; options = []; packages = []; tourPlan = nil
        isTyping = false; inputText = ""
        step = .country; selectedCountry = ""; selectedBudget = ""
        draftTour = .empty
        lastTourRequest = nil
        startFlow()
    }

    private func startFlow() {
        botDelay("Hello! I'm your Wayfari AI travel planner. Speak or type a trip idea — e.g. “Europe for 5 days” or “Canada USA for 10 days”. 🌍🎙️", after: 0.3)
        botDelay("If anything’s missing (like destination or number of days), I’ll ask. Or pick a country below:", after: 1.0) {
            self.options = self.countryOpts
        }
    }

    // MARK: - Tour planning with clarification

    /// Starts or continues a tour request; asks for anything still missing.
    private func handleTourPlanning(from text: String, alreadyLoggedUser: Bool = false) {
        if !alreadyLoggedUser { addUser(text) }
        options = []
        packages = []

        applyClarificationAnswer(text)

        let extracted = TourPlanGenerator.extractPartial(from: text)
        // Merge extras (days/travellers/destinations) without wiping a confirmed origin.
        let savedOriginCountry = draftTour.originCountry
        let savedOriginCity = draftTour.originCity
        draftTour.merge(from: extracted)
        if savedOriginCountry != nil {
            draftTour.originCountry = savedOriginCountry
            draftTour.originCity = savedOriginCity ?? draftTour.originCity
        }
        if draftTour.originCountry == nil, let origin = extracted.originCountry {
            draftTour.originCountry = origin
            draftTour.originCity = extracted.originCity
        }

        // Chip / typed destination when destinations still empty
        if draftTour.destinations.isEmpty {
            let cleaned = OriginCatalog.normalizeMatchingText(extractName(text).isEmpty ? text : extractName(text))
            let fromCatalog = TourPlanGenerator.matchDestinations(in: cleaned)
            if !fromCatalog.isEmpty {
                draftTour.destinations = fromCatalog
            }
        }

        if draftTour.isComplete {
            finalizeTourPlan()
            return
        }

        step = .clarifyingTour
        let prompt = TourPlanGenerator.clarificationMessage(for: draftTour)
        botDelay(prompt, after: 0.55) {
            self.presentClarificationOptions()
        }
    }

    /// Applies the user's reply to the *next* missing field so answers stick.
    private func applyClarificationAnswer(_ text: String) {
        let missing = draftTour.missingRequirements
        guard let next = missing.first else { return }
        let cleaned = OriginCatalog.normalizeMatchingText(text)

        switch next {
        case .destination:
            let dests = TourPlanGenerator.matchDestinations(in: cleaned)
            if !dests.isEmpty {
                draftTour.destinations = dests
                return
            }
            // User may answer departure first (e.g. tap Pakistan while we asked destination)
            if let origin = OriginCatalog.matchBareOriginAnswer(cleaned)
                ?? OriginCatalog.matchOrigin(in: "from \(cleaned)") {
                // Only treat as origin if it is not also a tour destination profile
                let asDest = TourPlanGenerator.matchDestinations(in: cleaned)
                if asDest.isEmpty {
                    draftTour.originCountry = origin.country
                    draftTour.originCity = origin.city
                }
            }

        case .days:
            if let days = TourPlanGenerator.parseDays(from: cleaned) {
                draftTour.days = days
            }

        case .originCountry:
            if let origin = OriginCatalog.matchBareOriginAnswer(cleaned)
                ?? OriginCatalog.matchOrigin(in: cleaned)
                ?? OriginCatalog.matchOrigin(in: "from \(cleaned)") {
                draftTour.originCountry = origin.country
                draftTour.originCity = origin.city
            }
        }

        // Always try to fill travellers from any reply
        if let travelers = TourPlanGenerator.parseTravelers(from: cleaned) {
            draftTour.travelers = travelers
        }
    }

    private func presentClarificationOptions() {
        // Show chips for only the next missing field
        guard let next = draftTour.missingRequirements.first else {
            self.options = []
            return
        }
        switch next {
        case .days:
            self.options = TourPlanGenerator.dayQuickOptions
        case .destination:
            self.options = self.countryOpts
        case .originCountry:
            self.options = OriginCatalog.quickOptions
        }
    }

    private func finalizeTourPlan() {
        draftTour.destinations = DestinationCatalog.normalized(draftTour.destinations)
        guard let resolved = draftTour.resolved() else {
            step = .clarifyingTour
            botDelay(TourPlanGenerator.clarificationMessage(for: draftTour), after: 0.5) {
                self.presentClarificationOptions()
            }
            return
        }

        options = []
        tourPlan = nil
        selectedCountry = resolved.destinations.joined(separator: " · ")
        step = .done
        let label = resolved.title
        let dayCount = resolved.days ?? 0
        let originLabel: String = {
            if let city = resolved.originCity, let country = resolved.originCountry {
                return "\(city), \(country)"
            }
            return resolved.originCountry ?? "your city"
        }()
        botDelay("Perfect — building your \(dayCount)-day plan for \(resolved.destinations.joined(separator: " & ")) departing from \(originLabel)… flights, hotels across popular cities, day-by-day itinerary & ticket prices. ✈️🏨🗺️", after: 0.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            self.isTyping = false
            let plan = TourPlanGenerator.generate(from: resolved)
            self.tourPlan = plan
            self.lastTourRequest = resolved
            self.draftTour = .empty
            self.addBot("Here’s your complete \(dayCount)-day plan for \(label), departing from \(originLabel). Switch tabs for Flights, Hotels, and the full Itinerary. Ask me anything else!")
        }
    }

    // MARK: - Option tap handler
    func pick(_ option: String) {
        options = []
        addUser(option)

        // Quick day chips or country chips while clarifying a tour
        if step == .clarifyingTour {
            handleTourPlanning(from: option, alreadyLoggedUser: true)
            return
        }

        switch step {
        case .country:
            selectedCountry = option
            // Prefer full tour flow: ask days next, then generate
            draftTour = .empty
            let name = extractName(option)
            let dests = TourPlanGenerator.matchDestinations(in: name.lowercased())
            draftTour.destinations = dests.isEmpty ? [name] : dests
            step = .clarifyingTour
            botDelay("Great choice — \(draftTour.destinations.joined(separator: " & "))! 🌟 How many days do you want to spend there?", after: 0.7) {
                self.options = TourPlanGenerator.dayQuickOptions
            }

        case .budget:
            selectedBudget = option
            step = .done
            let dest = extractName(selectedCountry)
            botDelay("Perfect! Generating personalised packages for \(dest) within \(option)... 🎉", after: 0.7)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                self.isTyping = false
                self.packages = SampleData.packages(country: dest, budget: option)
                self.addBot("Here are your 3 tailored packages 👆 Tap any card to expand the full breakdown. Feel free to ask me anything about your trip!")
            }

        case .clarifyingTour, .done:
            break
        }
    }

    // MARK: - Free-text / voice send handler
    func sendText() {
        let raw = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        inputText = ""
        processUserInput(raw)
    }

    func processUserInput(_ raw: String) {
        // Continue clarifying an in-progress tour
        if step == .clarifyingTour {
            handleTourPlanning(from: raw)
            return
        }

        // Update an existing plan when the user corrects travellers / days / origin
        if step == .done, var current = lastTourRequest {
            let patch = TourPlanGenerator.extractPartial(from: raw)
            var changed = false
            if let travelers = patch.travelers, travelers != current.travelers {
                current.travelers = travelers
                changed = true
            }
            if let days = patch.days, days != current.days {
                current.days = days
                changed = true
            }
            if let originCountry = patch.originCountry {
                current.originCountry = originCountry
                current.originCity = patch.originCity
                changed = true
            } else if OriginCatalog.matchOrigin(in: "from \(raw.lowercased())") != nil,
                      let origin = OriginCatalog.matchOrigin(in: "from \(raw.lowercased())") {
                current.originCountry = origin.country
                current.originCity = origin.city
                changed = true
            }
            if !patch.destinations.isEmpty, patch.destinations != current.destinations {
                current.destinations = DestinationCatalog.normalized(patch.destinations)
                changed = true
            }
            if changed {
                addUser(raw)
                draftTour = current
                finalizeTourPlan()
                return
            }
        }

        // New tour / package planning request
        if TourPlanGenerator.looksLikePlanningRequest(raw) {
            draftTour = .empty
            tourPlan = nil
            handleTourPlanning(from: raw)
            return
        }

        // If still awaiting country selection, match typed text to a country
        if step == .country {
            options = []
            let matched = countryOpts.first {
                $0.localizedCaseInsensitiveContains(raw)
                    || extractName($0).localizedCaseInsensitiveContains(raw)
            }
            if let matched {
                pick(matched)
            } else {
                addUser(raw)
                botDelay("I couldn't find '\(raw)' in my list. Try “Europe for 5 days”, or pick a country below.", after: 0.6) {
                    self.options = self.countryOpts
                }
            }
            return
        }

        // If still awaiting budget (legacy package path)
        if step == .budget {
            options = []
            let matched = budgetOpts.first {
                $0.localizedCaseInsensitiveContains(raw)
            }
            if let matched {
                pick(matched)
                return
            }
            if let number = Int(raw.filter(\.isNumber)), number > 0 {
                addUser(raw)
                let tier: String
                switch number {
                case ..<1000:   tier = budgetOpts[0]
                case ..<2000:   tier = budgetOpts[1]
                case ..<4000:   tier = budgetOpts[2]
                default:        tier = budgetOpts[3]
                }
                botDelay("Got it! I'll match that to the '\(tier)' range.", after: 0.5) {
                    self.pick(tier)
                }
                return
            }
            addUser(raw)
            botDelay("Please select your budget range from the options below. You can also type a number like '2000'.", after: 0.6) {
                self.options = self.budgetOpts
            }
            return
        }

        // ── Free Q&A after packages / plans are shown ──────────────────
        addUser(raw)
        let reply = generateReply(for: raw)
        botDelay(reply, after: 0.8)
    }

    // MARK: - Smart reply generator
    private func generateReply(for text: String) -> String {
        let lower = text.lowercased()
        let dest  = selectedCountry.isEmpty ? "your destination" : extractName(selectedCountry)
        let budgetCtx = selectedBudget.isEmpty ? "" : " within a \(selectedBudget) budget"

        for qa in qaBank {
            if qa.keywords.contains(where: { lower.contains($0) }) {
                return qa.reply
            }
        }

        if lower.hasPrefix("what") || lower.hasPrefix("which") {
            return "For \(dest)\(budgetCtx), the specifics depend on your travel dates and group size. Key things to check: entry requirements, local weather, and transport options. Want me to go deeper on any of these? 🗺️"
        }
        if lower.hasPrefix("how") {
            return "Getting around \(dest) is generally straightforward. Major cities have reliable public transport — Google Maps works well almost everywhere. Ride-hailing apps like Uber, Careem, or local equivalents cover most urban areas too. 🚌"
        }
        if lower.hasPrefix("when") {
            return "The ideal time to visit \(dest) is during shoulder season — just before or after peak season — for better prices and fewer crowds. Would you like a specific month-by-month breakdown? 📅"
        }
        if lower.hasPrefix("is ") || lower.hasPrefix("are ") || lower.hasPrefix("can ") || lower.hasPrefix("do ") || lower.hasPrefix("does ") {
            return "Great question about \(dest)! In most cases the answer is yes — it's a popular destination for travellers from all backgrounds. Is there a specific concern I can help clarify? ✅"
        }
        if lower.contains("compare") || lower.contains("difference") || lower.contains("vs") || lower.contains("better") {
            return "Great comparison question! Generally: higher-budget trips give you more comfort and less planning stress. Lower-budget trips require more flexibility but can be equally rewarding. For \(dest)\(budgetCtx), I'd recommend starting with the 4-star package for the best value-to-comfort ratio. 🎯"
        }
        if lower.contains("number") || lower.contains("how many") || lower.contains("price") || lower.contains("cost") {
            return "Costs in \(dest)\(budgetCtx): a mid-range meal runs $8–$20 per person, a local taxi ~$5–$15, and museum entry typically $5–$25. The packages above already include flights, hotel, and transport. 💰"
        }

        if let _ = text.rangeOfCharacter(from: .decimalDigits) {
            return "Based on that figure\(budgetCtx.isEmpty ? "" : " and your selected range"), the 3-star and 4-star packages above offer the best value. Tap any package card to see the full itemised breakdown including flights, hotel, taxi, food, and local transport. 💡"
        }

        let fallbacks = [
            "Great point about \(dest)! My advice: get travel insurance, keep digital copies of your passport, and download offline maps. Any other questions? 😊",
            "For \(dest)\(budgetCtx), flexibility is key. Book refundable options where possible and check visa requirements at least 3 weeks before departure. What else can I help with? 🌐",
            "That's worth looking into for \(dest). I'd recommend checking TripAdvisor and Google Reviews for the most current local insights alongside the packages above. Anything specific? 🔍",
            "Interesting question! \(dest) is a fantastic destination and most travellers have a wonderful experience there. Is there a specific aspect of the trip you'd like me to help plan? ✈️",
        ]
        return fallbacks[abs(text.hashValue) % fallbacks.count]
    }

    // MARK: - Helpers
    private func extractName(_ s: String) -> String {
        let parts = s.components(separatedBy: " ")
        // Drop leading emoji / flag cluster if present
        if parts.count > 1, parts[0].unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.value > 0x1F000 }) {
            return parts.dropFirst().joined(separator: " ")
        }
        return s.components(separatedBy: " ").dropFirst().joined(separator: " ").isEmpty
            ? s
            : s.components(separatedBy: " ").dropFirst().joined(separator: " ")
    }
    private func addBot(_ text: String) {
        messages.append(ChatMessage(role: .bot, text: text))
    }
    private func addUser(_ text: String) {
        messages.append(ChatMessage(role: .user, text: text))
    }
    private func botDelay(_ text: String, after: Double, then: (() -> Void)? = nil) {
        isTyping = true
        DispatchQueue.main.asyncAfter(deadline: .now() + after) {
            self.isTyping = false
            self.addBot(text)
            then?()
        }
    }
}

// MARK: - AIChatView
struct AIChatView: View {
    @Binding var isPresented: Bool
    @StateObject private var vm = ChatViewModel()
    @StateObject private var voice = VoiceInputService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {

                            ForEach(vm.messages) { msg in
                                BubbleView(message: msg).id(msg.id)
                            }

                            if vm.isTyping { TypingBubble() }

                            if !vm.options.isEmpty {
                                CountryOptionsGrid(
                                    options: vm.options,
                                    isBudget: vm.options.first?.contains("$") == true
                                        || vm.options.first?.localizedCaseInsensitiveContains("day") == true
                                        || vm.options.first.map { OriginCatalog.quickOptions.contains($0) } == true,
                                    onSelect: { vm.pick($0) }
                                )
                                .padding(.leading, 36)
                                .padding(.trailing, 4)
                            }

                            if let plan = vm.tourPlan {
                                TourPlanCard(plan: plan)
                                    .id("tourPlan")
                            }

                            if !vm.packages.isEmpty {
                                ForEach(vm.packages) { pkg in
                                    PackageCard(package: pkg)
                                }
                            }

                            Color.clear.frame(height: 12).id("bottom")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                    }
                    .onChange(of: vm.messages.count) { _ in
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onChange(of: vm.isTyping) { _ in
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onChange(of: vm.options.count) { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                    }
                    .onChange(of: vm.packages.count) { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                    }
                    .onChange(of: vm.tourPlan?.id) { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation { proxy.scrollTo("tourPlan", anchor: .top) }
                        }
                    }
                }
                .background(Theme.background)

                if voice.isListening || !voice.partialTranscript.isEmpty {
                    VoiceListeningBanner(
                        text: voice.partialTranscript.isEmpty ? "Listening… say your trip idea" : voice.partialTranscript,
                        onCancel: { voice.stop(); voice.clearTranscript() }
                    )
                }

                if let err = voice.errorMessage {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                }

                ChatInputBar(
                    text: $vm.inputText,
                    isListening: voice.isListening,
                    onSend: vm.sendText,
                    onMic: { handleMicTap() }
                )
            }
            .navigationTitle("Wayfari AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: vm.restart) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
            }
            .onChange(of: voice.transcript) { newValue in
                guard !newValue.isEmpty else { return }
                let spoken = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                voice.clearTranscript()
                guard !spoken.isEmpty else { return }
                vm.processUserInput(spoken)
            }
        }
    }

    private func handleMicTap() {
        if voice.isListening {
            voice.stop()
            let spoken = voice.partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !spoken.isEmpty {
                voice.clearTranscript()
                vm.processUserInput(spoken)
            }
        } else {
            voice.errorMessage = nil
            Task { await voice.start() }
        }
    }
}

private struct VoiceListeningBanner: View {
    let text: String
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .opacity(0.9)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Theme.label)
                .lineLimit(2)
            Spacer()
            Button("Done", action: onCancel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.accent.opacity(0.08))
        .overlay(Divider(), alignment: .top)
    }
}

// MARK: - Message bubble
struct BubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .bot {
                BotAvatar()
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.label)
                    .padding(.horizontal, 13).padding(.vertical, 10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(.systemGray5), lineWidth: 0.5))
                Spacer(minLength: 44)
            } else {
                Spacer(minLength: 44)
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 13).padding(.vertical, 10)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}

// MARK: - Bot avatar
struct BotAvatar: View {
    var body: some View {
        ZStack {
            Circle().fill(Theme.accent).frame(width: 28, height: 28)
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Typing indicator
struct TypingBubble: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.42, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            BotAvatar()
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color(.systemGray3))
                        .frame(width: 7, height: 7)
                        .scaleEffect(phase == i ? 1.45 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: phase)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(.systemGray5), lineWidth: 0.5))
            Spacer()
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}

// MARK: - Country & Budget grid
struct CountryOptionsGrid: View {
    let options: [String]
    let isBudget: Bool
    let onSelect: (String) -> Void

    private let twoCol = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        if isBudget {
            VStack(spacing: 8) {
                ForEach(options, id: \.self) { opt in
                    Button(action: { onSelect(opt) }) {
                        Text(opt)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .overlay(Capsule().stroke(Theme.accent, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(regionSections, id: \.region) { section in
                    Text(section.region)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.hint)
                        .tracking(0.5)
                        .padding(.top, 14)
                        .padding(.bottom, 4)

                    LazyVGrid(columns: twoCol, spacing: 8) {
                        ForEach(section.countries, id: \.self) { country in
                            Button(action: { onSelect(country) }) {
                                HStack(spacing: 6) {
                                    Text(flagOf(country)).font(.system(size: 17))
                                    Text(nameOf(country))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Theme.accent)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent.opacity(0.35), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func flagOf(_ s: String) -> String {
        String(s.unicodeScalars.prefix(while: {
            !CharacterSet.letters.union(.decimalDigits).contains($0)
        })).trimmingCharacters(in: .whitespaces)
    }
    private func nameOf(_ s: String) -> String {
        s.components(separatedBy: " ").dropFirst().joined(separator: " ")
    }

    private struct RegionGroup { let region: String; let countries: [String] }

    private var regionSections: [RegionGroup] {
        let defs: [(String, [String])] = [
            ("🌙 Middle East & Gulf", [
                "🇦🇪 UAE / Dubai","🇸🇦 Saudi Arabia","🇦🇿 Azerbaijan","🇲🇻 Maldives",
                "🇴🇲 Oman","🇶🇦 Qatar","🇧🇭 Bahrain","🇰🇼 Kuwait",
            ]),
            ("🌏 South Asia", [
                "🇵🇰 Pakistan","🇮🇳 India","🇱🇰 Sri Lanka","🇧🇩 Bangladesh","🇳🇵 Nepal",
            ]),
            ("🌏 Southeast & East Asia", [
                "🇲🇾 Malaysia","🇨🇳 China","🇯🇵 Japan","🇰🇷 South Korea",
                "🇹🇭 Thailand","🇸🇬 Singapore","🇮🇩 Indonesia","🇻🇳 Vietnam",
            ]),
            ("🇪🇺 Schengen Zone", [
                "🇩🇪 Germany","🇫🇷 France","🇮🇹 Italy","🇪🇸 Spain",
                "🇳🇱 Netherlands","🇧🇪 Belgium","🇦🇹 Austria","🇨🇭 Switzerland",
                "🇵🇹 Portugal","🇬🇷 Greece","🇸🇪 Sweden","🇳🇴 Norway",
                "🇩🇰 Denmark","🇫🇮 Finland","🇨🇿 Czech Republic","🇵🇱 Poland",
                "🇭🇺 Hungary","🇸🇰 Slovakia","🇸🇮 Slovenia","🇭🇷 Croatia",
                "🇷🇴 Romania","🇧🇬 Bulgaria","🇱🇺 Luxembourg","🇲🇹 Malta",
                "🇮🇸 Iceland","🇱🇮 Liechtenstein","🇪🇪 Estonia","🇱🇻 Latvia","🇱🇹 Lithuania",
            ]),
            ("🌍 Non-Schengen Europe", [
                "🇬🇧 United Kingdom","🇮🇪 Ireland","🇹🇷 Turkey",
                "🇷🇸 Serbia","🇲🇰 North Macedonia","🇦🇱 Albania",
                "🇲🇪 Montenegro","🇧🇦 Bosnia & Herzegovina","🇺🇦 Ukraine","🇬🇪 Georgia",
            ]),
            ("🌎 Americas", [
                "🇺🇸 United States","🇨🇦 Canada","🇲🇽 Mexico",
                "🇧🇷 Brazil","🇦🇷 Argentina","🇨🇴 Colombia","🇵🇪 Peru","🇨🇱 Chile",
            ]),
            ("🌏 Oceania", [
                "🇦🇺 Australia","🇳🇿 New Zealand","🇫🇯 Fiji",
            ]),
            ("🌍 Africa", [
                "🇿🇦 South Africa","🇰🇪 Kenya","🇲🇦 Morocco","🇪🇬 Egypt","🇹🇿 Tanzania",
            ]),
        ]
        return defs.compactMap { region, all in
            let filtered = all.filter { options.contains($0) }
            return filtered.isEmpty ? nil : RegionGroup(region: region, countries: filtered)
        }
    }
}

// MARK: - Package card
struct PackageCard: View {
    let package: TravelPackage
    @State private var expanded = false

    private var tierColors: (fg: Color, bg: Color) {
        switch package.tier {
        case .luxury:  return (Color(hex: "8A6000"), Color(hex: "FFF3D0"))
        case .comfort: return (Color(hex: "1A5CAA"), Color(hex: "E8F0FB"))
        case .budget:  return (Color(hex: "2E7D32"), Color(hex: "E8F5E9"))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    PillBadge(text: "\(package.tier.stars)  \(package.tier.rawValue)",
                              foreground: tierColors.fg, background: tierColors.bg)
                    Text(package.name).font(.system(size: 16, weight: .semibold))
                    Text("$\(package.pricePerPerson)/person  ·  \(package.nights) nights")
                        .font(.system(size: 13)).foregroundColor(Theme.sublabel)
                }
                Spacer()
                Button(action: { withAnimation(.spring(response: 0.28)) { expanded.toggle() } }) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.sublabel)
                        .frame(width: 28, height: 28)
                        .background(Color(.systemGray5), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)

            if expanded {
                Divider()
                VStack(spacing: 0) {
                    ForEach(Array(package.items.enumerated()), id: \.element.id) { idx, item in
                        PackageRow(item: item)
                        if idx < package.items.count - 1 { Divider().padding(.leading, 54) }
                    }
                }
                Divider()
                Button(action: {}) {
                    Text("Book This Package")
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain).padding(14)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray5), lineWidth: 0.5))
    }
}

// MARK: - Package row
struct PackageRow: View {
    let item: PackageLineItem

    var iconBg: Color {
        switch item.icon {
        case "airplane":   return Color(hex: "E0EEFF")
        case "building.2": return Color(hex: "FFF0E0")
        case "car.fill":   return Color(hex: "E8FFE8")
        case "fork.knife": return Color(hex: "FFE8E8")
        default:           return Color(hex: "F0E8FF")
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(iconBg).frame(width: 30, height: 30)
                Image(systemName: item.icon).font(.system(size: 14)).foregroundColor(Theme.label)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 13, weight: .medium))
                Text(item.detail).font(.system(size: 11)).foregroundColor(Theme.sublabel)
            }
            Spacer()
            Text("$\(item.price)").font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }
}

// MARK: - Chat input bar
struct ChatInputBar: View {
    @Binding var text: String
    var isListening: Bool = false
    let onSend: () -> Void
    var onMic: (() -> Void)? = nil

    var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: 8) {
            if let onMic {
                Button(action: onMic) {
                    ZStack {
                        if isListening {
                            Circle()
                                .fill(Color.red.opacity(0.15))
                                .frame(width: 36, height: 36)
                        }
                        Image(systemName: isListening ? "waveform.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(isListening ? .red : Theme.accent)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isListening ? "Stop listening" : "Voice input")
            }

            TextField(isListening ? "Listening…" : "Say or type: Europe for 5 days…", text: $text)
                .font(.system(size: 15))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(.systemGray5), in: Capsule())
                .disabled(isListening)
                .onSubmit { if canSend { onSend() } }

            Button(action: { if canSend { onSend() } }) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(canSend ? Theme.accent : Color(.systemGray3), in: Circle())
                    .animation(.easeInOut(duration: 0.15), value: canSend)
            }
            .buttonStyle(.plain)
            .disabled(isListening)
        }
        .padding(.horizontal, 12).padding(.vertical, 10).padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }
}

#Preview {
    AIChatView(isPresented: .constant(true))
}
