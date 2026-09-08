# Working Game Design: Historical Armies Idle Clicker

## Document status and confirmed requirements

This is a working design document assembled from the supplied discussion, not an approved implementation specification. The user's confirmed requirements are an **offline, single-player idle clicker** mixing historical armies from periods before gunpowder; both attack and defense; resets that return the campaign to **level 1** while retaining selected upgrades and accelerating progression through earlier levels; and an eventual **Android release**. These requirements define the intended game. They do not approve every mechanic described below.

Unless explicitly identified as a confirmed requirement, the specific mechanics, names, examples, and scope in this document are **mentor proposals** for discussion and testing. The proposed first playable slice is deliberately smaller than the long-term vision. Open decisions remain open; no engine, framework, implementation architecture, or asset workflow is selected here.

Offline operation and closed-app progression are separate concepts. Offline operation means the single-player game must work without an internet connection. Closed-app progression means deciding what rewards accrue while the application is not running. The first is confirmed; the particular rules for the second are proposed below.

## Vision: the army ends, the military tradition survives

The proposed fantasy is that the player builds a military institution rather than simply clicks away enemy health bars. A modest war camp becomes a capable army, conquers a campaign, and eventually passes its knowledge to a successor dynasty. A campaign can end and its territories can be surrendered without making the player's entire history disappear. The lasting achievement is the military tradition that becomes stronger across successive armies.

The historical mixture would be intentional rather than forced into a realistic chronology. The proposed setting is a fictional world inspired by pre-gunpowder warfare, where disciplined heavy infantry, mounted archers, chariot crews, spear formations, and siege engineers can coexist. Recognizable historical influences supply identities and tactical expectations, while the fictional premise permits combinations and balancing that would not claim historical accuracy. This setting explanation is a proposal, not an additional confirmed requirement.

The camp is proposed as the player's recurring anchor. The discussion imagines a commander, a few tents, a wooden barricade, and recruits developing into training grounds, fortified gates, horse enclosures, workshops, and standards representing recruited cultures. The purpose is to make advancement recognizable without requiring the player to inspect every number. These images preserve the experiential intent, but visual design and asset production are deferred; they are not an approved art direction or a production checklist.

## Player experience

The intended experience alternates between watching an army succeed, identifying a weakness, making an improvement, and seeing that improvement matter. Buying an upgrade should produce a noticeable change in battle. A player who cannot secure the next region should understand whether the problem is insufficient damage, a collapsing frontline, or an exposed back line, rather than assume that an invisible collection of bonuses decided the outcome.

Failure is proposed as feedback, not destruction of invested time. A lost battle should communicate that the current approach is not ready, without deleting purchased troops and creating an extended recovery chore. A productive fallback keeps the player earning resources while they save for improvements or reconsider their formation. This is particularly important in an idle game: the player should not need to supervise every encounter to protect an evening's progress.

The emotional payoff is a complete arc: struggle to take a region, strengthen the army, finally hold the gate against retaliation, then found a new dynasty and discover how much easier those earlier obstacles have become. A large roster or elaborate permanent upgrade tree is valuable only if it improves this experience.

## Core loop: prepare, conquer, withstand retaliation

The proposed ordinary loop is automatic combat through campaign stages, victories that award gold, and purchases of units or improvements that allow the army to advance farther. Gold is the proposed spendable battle currency, not a confirmed name. The player prepares an army, observes its battles, and adjusts its strength or composition as obstacles emerge.

Each region would culminate in an enemy stronghold. Defeating the stronghold triggers a counterattack against the camp, and surviving that assault secures the region and its reward. The resulting rhythm is advance, defeat the stronghold, withstand retaliation, and secure the milestone. Conquest is therefore not complete merely because the player can deal enough damage to win an offensive battle; the army must also hold its gains.

When the next obstacle cannot be cleared, the army can farm the last secured stage. This fallback gives the player time to accumulate an upgrade without requiring repeated manual attempts at a battle they cannot yet win. The exact handling of an unsuccessful counterattack, including retry placement and interim rewards, remains undecided. The productive fallback and non-destructive defeat principles should constrain that decision.

## Active versus idle play

Tapping is proposed to issue a commander's strike from the beginning of the game. It could be represented as a volley, a focused attack, or marking an enemy for concentrated fire. These are alternative representations of the same proposed direct contribution, not three separate initial mechanics. The army continues attacking automatically, while tapping helps overcome troublesome opponents sooner and preserves a recognizable clicker identity.

The commander's contribution should remain meaningful as the army grows. Otherwise, tapping becomes repeated finger movement for negligible benefit. Partial scaling with army strength is one suggested solution to test, not a settled damage formula. Active play should provide a useful advantage without making constant tapping the only practical route forward.

A later expansion could add a small number of tactical abilities. Rally could temporarily increase army output; Shield Wall could reduce incoming damage; and a focused volley could remove a dangerous back-line enemy. Their purpose would be occasional satisfying choices, not an attention tax that requires continuous input. These abilities are outside the proposed first slice, which needs only the commander tap.

The core balance principle is that active play accelerates a functioning idle game rather than rescues a deliberately crippled one. Verification should include playing with no tapping at all. The mere existence of automatic attacks does not prove that passive progress is meaningful. Active and idle runs must both be evaluated before deciding how large the active advantage should become.

## Army roles and historical identities

The proposed starting role set is frontline, ranged, and mobile. Frontline units absorb pressure and hold enemies in place. Ranged units provide steady damage but need protection. Mobile units deliver bursts of damage or exploit vulnerable targets. Siege units belong later, once enemy fortifications are meaningful enough to justify a specialized answer rather than another damage purchase.

Historical inspiration would distinguish behavior within these roles. A Roman-inspired shield unit could reliably protect troops behind it. A Greek-inspired spear formation could resist charges while being less flexible against ranged pressure. Steppe horse archers could exchange durability for sustained harassment. Chariot crews also belong to the broader pre-gunpowder fantasy, but their precise mechanics have not been chosen. These examples describe game identities, not claims that a whole historical army can be reduced to one ability.

New units should create useful alternatives rather than automatically invalidate earlier purchases. An infantry unlock with more health, more damage, and a better ability in every circumstance is primarily a replacement, not a strategic choice. A durable shield unit and an aggressive assault unit can instead remain relevant in different encounters. This makes campaign variety and composition decisions reinforce each other.

Three actual unit types are proposed for the first playable version, using the three-role starting model without treating specific historical cultures as selected. That is enough to test whether protecting ranged damage with infantry is satisfying and whether a mobile role adds value. A broad collection of cultures is a long-term possibility, not a prerequisite for testing the game. Formation controls, targeting rules, and the exact initial roster remain unresolved.

## Attack and defense

The latest proposal uses the **same army sequentially in both attack and defense**. It explicitly supersedes the earlier suggestion of dividing forces between a conquering expedition and a home garrison. Splitting the army could add allocation chores before combat itself has proven enjoyable. Separate expeditions remain a possible later alternative only if they solve a demonstrated need; they are not part of the initial design direction.

Offense emphasizes defeating enemy formations before they wear the army down. Defense emphasizes surviving an assault while protecting the camp. An aggressive composition might clear ordinary battles quickly but struggle when attackers reach its fragile back line. A defensive composition might hold reliably while taking longer to conquer. These different pressures should make one roster interesting in both phases without creating two unrelated games.

The proposed camp gate has its own health. Frontline troops protect it, ranged units fight behind it, and enemies that break through begin damaging the gate. Defensive victory requires surviving the assault with the camp intact. This gives defense a distinct failure condition rather than merely reversing the background of an offensive encounter. The precise assault completion rule, such as defeating all attackers or surviving a defined duration, has not been settled.

Fortifications could expand that defensive preparation without turning the game into a full tower-defense project. A stronger gate buys time, archer platforms improve ranged support, and a defensive ditch weakens an opening charge. The intent is to prepare a camp, not draw maze routes or place dozens of individual towers. Only the gate is included in the proposed first slice; the other fortifications are examples for later consideration.

Counterattacks are proposed to follow campaign progress, not a real-world attendance schedule. This replaces the earlier “conquer by day, defend by night” concept wherever that would require scheduled play. The player should not return after sleeping to find the camp destroyed for failing to be present. Losing an attempted battle and being punished for absence are different things; only the former belongs in this proposed loop.

The earlier discussion suggested separate attack gold and defense supplies. The latest first-slice proposal instead specifies **one spendable battle currency**, with gold as the working name. A separate supplies economy is not included in that slice, and the broader need for it remains unapproved. Defense already matters because holding the camp is required to secure a region; it does not need a second currency merely to justify its existence.

## Progression and resets

Returning to level 1 while retaining selected upgrades is confirmed. The proposed thematic form is **Found a Dynasty**: retire the current campaign and convert its achievements into **Legacy**, a permanent resource representing inherited military knowledge. Under this proposal, territory, gold, troop levels, and camp construction reset, while unlocked military traditions and purchased doctrines remain. These particular reset boundaries and names are proposals; the confirmed requirement is selective retention and faster earlier progression.

Legacy would come mainly from the highest secured campaign milestone, with a visible preview of what reaching the next milestone earns. This ties prestige to completing the attack-and-defense rhythm rather than merely reaching an arbitrary damage total. Its intended incentive is a considered decision about when a campaign has run its course, rather than an optimal strategy of resetting every ninety seconds. The precise formula, repeat-run rewards, and reset availability still need to be chosen.

Permanent upgrades should include **both numerical power gains and occasional changes to play**. This is the latest explicit direction and replaces the earlier claim that permanent upgrades should change strategy rather than merely multiply damage. Straightforward improvements are part of an idle game's reset payoff: faster training, stronger starting troops, or a stronger commander make an old obstacle visibly easier. Strategic and convenience unlocks give the player longer-term direction alongside that immediate strength.

For example, a logistics doctrine might automatically buy early troop levels, while a veteran cadre might provide an established frontline at the start of a dynasty. These are possible expressions of institutional memory, not an approved automation tree. They would reduce repeated setup and make the army feel as though it retained what previous campaigns learned.

The first reset must demonstrate its value quickly. The proposed experience is returning to the opening battlefield with faster recruitment, stronger commander attacks, or another clear retained advantage, then finding the first defensive assault easier. These examples do not require the first slice to implement every benefit. Its single Legacy upgrade should be enough to prove that the second campaign is meaningfully faster, rather than a manual replay of the tutorial.

## Campaign variety

Regions can test different weaknesses without introducing a large stack of new systems. An open plain might feature enemy cavalry that punishes a flimsy frontline. A fortified settlement might demand sustained damage against durable defenders. An archer-dominated region might challenge protection of vulnerable units or the ability to reach an enemy back line.

The proposed initial method is enemy composition plus one clearly displayed regional modifier. This keeps the source of difficulty legible. A player should be able to conclude, “Their cavalry broke through my infantry,” or, “I survived, but could not kill the defenders quickly enough.” Hidden interactions among many bonuses would undermine that understanding and turn composition changes into guesswork.

Weather simulation, supply routes, morale, diplomacy, equipment rarity, and terrain pathfinding are not part of the initial proposal. Each might be interesting individually, but combining them prematurely would bury the readable core game. Regional variety is a broader direction; a single-region first slice does not need a full modifier catalogue.

Over time, securing regions could unlock new military traditions. The player would encounter a distinctive enemy, learn to defeat it, and eventually gain access to related warfare. That makes discovery part of the campaign rather than a giant shop visible from the start. The relationship between these unlocks and permanent retention fits the dynasty premise, but the unlock schedule and expanded roster remain undecided.

## Offline behavior and closed-app progression

The confirmed offline single-player requirement means the core game must remain playable without internet connectivity. It does not imply that an army must fight every battle while the app is closed, nor that the game needs an online service to award idle rewards. No network-dependent progression mechanic is approved by this document.

For time spent away from the app, the mentor proposes capped rewards from already secured territory. Under that rule, the player returns with resources to spend, but the game does not automatically defeat unknown bosses or complete defensive milestones. Routine earning continues in a bounded form while the important campaign decisions and first-time victories remain available to experience. The reward cap, earning rate, eligible territory, and presentation have not been chosen.

Automatic combat during an open session is distinct from this closed-app reward rule. The army can fight automatically during normal play, while returning from an absence need not simulate every missed battle or advance into uncleared regions. Whether an open but unattended session pauses at particular milestones is still an open decision; it should not be silently inferred from the rules for a closed app.

The no-absence-punishment direction also applies here. Counterattacks should not destroy the camp while the player is away because a clock expired. Persistence and elapsed-time handling must eventually support the selected rules, but save format, timing policy, and technical implementation remain deferred until tools and behavior are chosen.

## Android considerations and deferred presentation work

An eventual Android release is confirmed; immediate Android packaging is not part of the approved scope. The design should account for touch interaction and short sessions without expanding the first playable into a complete mobile production effort.

The mentor suggests portrait play, with battle and campaign progress above the commander action and important purchases. Army composition, camp upgrades, and Legacy could occupy separate screens, provided ordinary play does not require constant navigation among them. These are usability proposals to retain for later evaluation, not a settled interface design. Visual direction is deferred.

The discussion also suggests conveying an army through a few representative squads rather than individually simulating every owned recruit. Clear motion and silhouettes could preserve readability as troop counts become enormous, without relying on tiny labels over dozens of soldiers. This records the intended readability and scale tradeoff, not a rendering technology or approved art workflow.

Engine and framework selection, Unity, Blender, AI asset workflows, and detailed visuals are explicitly deferred. No technology recommendation has been verified or selected. Android export, packaging, and platform-specific implementation decisions should be evaluated when choosing tools, not asserted as already solved by this brainstorm.

## Proposed first playable scope

The proposed first playable is one small campaign that ends in a reset and allows a second run to demonstrate the retained benefit. It contains three unit types, one spendable battle currency, automatic army combat, a commander tap, a camp gate, one stronghold, one defensive assault, and one Legacy upgrade that makes the next run noticeably faster. Legacy is the proposed permanent reset resource, distinct from the single currency spent on ordinary battle improvements; “one battle currency” does not eliminate the reset reward concept.

That slice should connect its systems rather than present isolated demonstrations. The player upgrades the army, reaches and defeats the stronghold, survives the counterattack, secures the campaign milestone, resets to level 1, and experiences accelerated earlier progress. A last-secured-stage fallback and non-destructive failure are part of the proposed behavior that makes this loop playable without recovery chores. Exact stage counts, costs, battle parameters, and which Legacy upgrade proves the reset remain open.

The slice exists to answer a small set of substantive questions: is watching combat satisfying, does an upgrade visibly help, does defense create a different consideration from attack, can the player progress without constant tapping, and does resetting feel like gaining power rather than losing work? These should be observed and behavior-tested, not assumed from the presence of the corresponding buttons or systems.

The full historical roster, siege units, multiple regions, advanced tactical abilities, separate expeditions, additional battle currencies, elaborate doctrines, and expanded fortifications are not included in this proposed first scope. The gate provides a defensive objective without committing to a tower-defense game. Closed-app rewards are a proposed broader behavior whose inclusion in the first slice is unresolved; they should not be silently added to the minimal campaign. Likewise, no polished assets or Android release build are implied. The slice itself remains a proposal for approval, not authorization to implement the entire document.

## Development principles

Development should proceed through small, single-purpose modules. Game rules and state should be separated from UI and rendering so that changing presentation does not redefine how a battle, purchase, or reset works. Combat, economy/progression, prestige, and persistence should remain independently testable. These are development constraints, not a mandate for a complex framework, a large abstraction hierarchy, or a particular directory layout.

One focused slice should be implemented and behavior-tested before moving to the next. Within the proposed first playable, this means verifying a coherent behavior before layering on additional mechanics, then checking that the connected loop still behaves correctly. Appropriate checks include automatic progress without taps, the effect of a purchase, gate survival and defeat, productive fallback, and the exact state that a reset removes or preserves. Persistence should be checked independently for saving and restoring the intended state when it is introduced. These examples express expected behavior without choosing a test library or engine.

Do not invent a complex architecture before selecting the tools. Choose only enough structure to keep responsibilities clear and tests practical, and let demonstrated needs justify further structure. No code, dependency installation, engine choice, visual production, or asset workflow is part of this documentation task.

## Open decisions and direction changes

The central requirements are confirmed, but the fictional dynasty premise, commander's strike presentation, exact starting units, formation controls, targeting behavior, upgrade costs, combat formulas, and balance between active and idle progress remain proposals or open choices. Offensive failure timing and the precise defensive win condition also need definition. The document does not resolve those choices by merging all examples into one feature set.

Prestige still needs a Legacy calculation, reset eligibility, repeat-milestone reward rules, the first permanent upgrade, and a final retention list. “Unlocked traditions survive” and “troop levels reset” can coexist, but the implementation will need to distinguish access to a unit type from the temporary strength or ownership of troops in a run. Similarly, a veteran starting frontline is an example of a purchased permanent benefit, not a promise that all purchased troops survive every reset.

Closed-app progression needs its cap, reward rate, timing policy, and first-slice inclusion decided. Open-session idling at strongholds or counterattacks is separately unresolved. The proposed distinction is deliberate: playable without internet, automatic combat while open, and rewards while closed are three different behaviors.

Several apparent conflicts have an explicit later direction. Use the same army for sequential offense and defense rather than initially splitting an expedition and garrison. Trigger counterattacks through campaign progress rather than scheduled day/night attendance. Include numerical prestige gains alongside strategic and convenience unlocks rather than rejecting simple multipliers. Use one spendable battle currency in the first slice rather than requiring separate gold and supplies economies. These later proposals supersede the earlier alternatives but do not become user-confirmed mechanics merely by being the latest suggestions.

The phrase “your army dies, your military tradition survives” describes the proposed campaign-scale fantasy; it is not a literal instruction to delete purchased troops after an ordinary defeat. The detailed non-destructive failure proposal takes precedence. Retirement and dynasty succession can carry the theme without contradicting the intended idle-game safety of routine battles.

Finally, the intended camp growth and portrait presentation are retained as experience references while visuals remain deferred. Tools, framework, Unity, Blender, AI asset workflows, and Android packaging are unchosen. There is no unresolved direct contradiction in the confirmed requirements; the remaining work is to approve a bounded slice and settle the explicitly open mechanics without treating the full brainstorm as committed scope.
