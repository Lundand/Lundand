--!strict
-- NPC conversations (L-40). Server-only, so story lines and their effects never reach clients early.
-- Each conversation has: npc; priority (the highest matching one wins); requires (conditions); onStart
-- (effects applied the moment it starts, so skipping text can never skip them); journal (a summary kept
-- for the journal); nodes (lines, then either next or choices, and choices carry actions).
-- Every NPC needs one conversation without requires as a fallback. Wording is first-draft content.
local Table = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Util.Table)

local function line(...: string): {string}
	return { ... }
end

return Table.deepFreeze({
	-- The King of Lundand
	KingGreeting = {
		npc = "TheKing",
		nodes = {
			start = { lines = line(
				"You stand before the throne of House Lundand, traveller.",
				"The Adventurers' Guild vouches for those it trusts. Return when your name is in its ledger."
			) },
		},
	},
	KingFirstAudience = {
		npc = "TheKing",
		priority = 10,
		requires = { questCompleted = "AdventurerRegistration", questNotStarted = "TheCrystalsUnease" },
		journal = { title = "An audience with the King", summary = "The King asked me to learn what the Old Scholar believes about the Heart of Realms." },
		nodes = {
			start = { lines = line(
				"So the Guild sends me another adventurer. Good. Lundand has need of steady hands.",
				"For three nights the runes on the Heart of Realms have flickered. My family has guarded that crystal longer than our records remember.",
				"I would know what the old stories say before I trust what my advisers tell me."
			), next = "ask" },
			ask = {
				lines = line("A scholar keeps watch by the crystal. Hear what he believes, and bring it to me."),
				choices = {
					{ text = "I'll speak with him.", actions = { { kind = "AcceptQuest", questId = "TheCrystalsUnease" } } },
					{ text = "Not yet, Your Majesty." },
				},
			},
		},
	},
	KingAwaitsReport = {
		npc = "TheKing",
		priority = 20,
		requires = { questActive = "TheCrystalsUnease" },
		nodes = {
			start = {
				lines = line("Have you spoken with the scholar?"),
				choices = {
					{
						text = "He told me the old legends.",
						requires = { questReady = "TheCrystalsUnease" },
						actions = { { kind = "TurnInQuest", questId = "TheCrystalsUnease" } },
						next = "after",
					},
					{ text = "Not yet." },
				},
			},
			after = { lines = line(
				"Seals that weaken... I had hoped it was only an old man's fear.",
				"Say nothing of this in the square. Panic is a poor guardian. I will call for you again."
			) },
		},
	},
	KingLater = {
		npc = "TheKing",
		priority = 5,
		requires = { questCompleted = "TheCrystalsUnease" },
		nodes = { start = { lines = line("My scholars are searching the archives. Keep your blade ready, adventurer.") } },
	},

	-- The Old Scholar by the crystal: legends, not certainties
	ScholarRumours = {
		npc = "OldScholar",
		nodes = { start = { lines = line(
			"Beautiful, isn't it? They say the Heart of Realms was old before the first king was crowned.",
			"Some say it fell from the sky. Others say it was carved from the door of another world. I suspect both are wrong."
		) } },
	},
	ScholarLegend = {
		npc = "OldScholar",
		priority = 10,
		requires = { questActive = "TheCrystalsUnease" },
		journal = { title = "The Old Scholar's legend", summary = "The scholar believes the crystal once sealed tears between worlds, and that seals can tire. The court historians disagree." },
		nodes = { start = { lines = line(
			"The King sent you? Then he is more worried than he lets the court see.",
			"The oldest songs speak of tears in the sky, and of things that walked out of other worlds. The crystal sealed them.",
			"If the runes flicker, the seals are tired. Seals are promises, and promises can break.",
			"Mind you, the court historians call that a peasant's song. Tell the King both versions."
		) } },
	},

	-- Adventurers' Guild
	RegistrarWelcome = {
		npc = "GuildRegistrar",
		priority = 10,
		requires = { questNotCompleted = "AdventurerRegistration" },
		nodes = {
			start = { lines = line("Welcome to the Adventurers' Guild. Bounties, escorts, ruins: if it's dangerous and it pays, it comes through here."), next = "offer" },
			offer = {
				lines = line("Want your name in the ledger?"),
				choices = {
					{
						text = "Sign me up.",
						requires = { questNotStarted = "AdventurerRegistration" },
						actions = { { kind = "AcceptQuest", questId = "AdventurerRegistration" } },
						next = "sign",
					},
					{
						text = "Here's my signature.",
						requires = { questReady = "AdventurerRegistration" },
						actions = { { kind = "TurnInQuest", questId = "AdventurerRegistration" } },
						next = "done",
					},
					{ text = "Not today." },
				},
			},
			sign = {
				lines = line("Sign here, and here. Mind the ink."),
				choices = {
					{
						text = "Here's my signature.",
						requires = { questReady = "AdventurerRegistration" },
						actions = { { kind = "TurnInQuest", questId = "AdventurerRegistration" } },
						next = "done",
					},
				},
			},
			done = { lines = line(
				"Welcome aboard. Check with me for bounties, and see the clerk if you want company on the road.",
				"And the King has been asking for capable adventurers. A rare honour."
			) },
		},
	},
	RegistrarBounties = {
		npc = "GuildRegistrar",
		nodes = {
			start = {
				lines = line("Back again? Today's bounties are on the board behind me."),
				choices = {
					{ text = "Take the wolf bounty.", requires = { questOffered = "BountyForestPests", questAvailable = "BountyForestPests" }, actions = { { kind = "AcceptQuest", questId = "BountyForestPests" } } },
					{ text = "Take the herb bounty.", requires = { questOffered = "BountyHerbBundle", questAvailable = "BountyHerbBundle" }, actions = { { kind = "AcceptQuest", questId = "BountyHerbBundle" } } },
					{ text = "Take the copper bounty.", requires = { questOffered = "BountyCopperRun", questAvailable = "BountyCopperRun" }, actions = { { kind = "AcceptQuest", questId = "BountyCopperRun" } } },
					{ text = "The wolves are dealt with.", requires = { questReady = "BountyForestPests" }, actions = { { kind = "TurnInQuest", questId = "BountyForestPests" } } },
					{ text = "Here are the herbs.", requires = { questReady = "BountyHerbBundle" }, actions = { { kind = "TurnInQuest", questId = "BountyHerbBundle" } } },
					{ text = "Here's the copper.", requires = { questReady = "BountyCopperRun" }, actions = { { kind = "TurnInQuest", questId = "BountyCopperRun" } } },
					{ text = "Any contracts for my guild?", requires = { questAvailable = "ContractWolfCulling" }, actions = { { kind = "AcceptQuest", questId = "ContractWolfCulling" } } },
					{ text = "I'll bring ore for the halls.", requires = { questAvailable = "ContractOreForTheHalls" }, actions = { { kind = "AcceptQuest", questId = "ContractOreForTheHalls" } } },
					{ text = "The wolf contract is done.", requires = { questReady = "ContractWolfCulling" }, actions = { { kind = "TurnInQuest", questId = "ContractWolfCulling" } } },
					{ text = "Here's the ore for the halls.", requires = { questReady = "ContractOreForTheHalls" }, actions = { { kind = "TurnInQuest", questId = "ContractOreForTheHalls" } } },
					{ text = "I'd like to see the player guilds.", actions = { { kind = "OpenGuildDesk" } } },
					{ text = "Just passing through." },
				},
			},
		},
	},
	PartyBoard = {
		npc = "PartyClerk",
		nodes = {
			start = {
				lines = line("Looking for company? The board lists every group recruiting today."),
				choices = {
					{ text = "Show me the party board.", actions = { { kind = "OpenPartyBoard" } } },
					{ text = "Maybe later." },
				},
			},
		},
	},

	-- Craftsmen's Guild and its workshops
	StewardIntroductions = {
		npc = "GuildSteward",
		nodes = {
			start = {
				lines = line("The Craftsmen's Guild trains anyone willing to work. The forge and the apothecary both take apprentices."),
				choices = {
					{ text = "Teach me smithing.", requires = { questAvailable = "CraftsmenIntroForge" }, actions = { { kind = "AcceptQuest", questId = "CraftsmenIntroForge" } } },
					{ text = "Teach me brewing.", requires = { questAvailable = "CraftsmenIntroBrewing" }, actions = { { kind = "AcceptQuest", questId = "CraftsmenIntroBrewing" } } },
					{ text = "My forge work is done.", requires = { questReady = "CraftsmenIntroForge" }, actions = { { kind = "TurnInQuest", questId = "CraftsmenIntroForge" } } },
					{ text = "My brewing work is done.", requires = { questReady = "CraftsmenIntroBrewing" }, actions = { { kind = "TurnInQuest", questId = "CraftsmenIntroBrewing" } } },
					{ text = "Goodbye." },
				},
			},
		},
	},
	ForgeMasterApprentice = {
		npc = "ForgeMaster",
		nodes = {
			start = {
				lines = line("The Steward sent you? Bring ore and logs, and keep your fingers out of the fire."),
				choices = {
					{ text = "I need tools.", actions = { { kind = "OpenShop", shop = "ForgeTools" } } },
					{ text = "Goodbye." },
				},
			},
		},
	},
	ForgeMasterWork = {
		npc = "ForgeMaster",
		priority = 10,
		requires = { questCompleted = "CraftsmenIntroForge" },
		nodes = {
			start = {
				lines = line("The anvil's free. My fee is fair; the work is yours."),
				choices = {
					{ text = "Use the forge.", actions = { { kind = "OpenCrafting", facilityId = "CityBlacksmith" } } },
					{ text = "I need tools.", actions = { { kind = "OpenShop", shop = "ForgeTools" } } },
					{ text = "Another time." },
				},
			},
		},
	},
	ApothecaryApprentice = {
		npc = "Apothecary",
		nodes = {
			start = {
				lines = line("Herbs first, then patience. The Guild Steward will tell you what to gather."),
				choices = {
					{ text = "I'd like some potions.", actions = { { kind = "OpenShop", shop = "ApothecaryPotions" } } },
					{ text = "Goodbye." },
				},
			},
		},
	},
	ApothecaryWork = {
		npc = "Apothecary",
		priority = 10,
		requires = { questCompleted = "CraftsmenIntroBrewing" },
		nodes = {
			start = {
				lines = line("Mind the copper pots; they bite."),
				choices = {
					{ text = "Use the apothecary.", actions = { { kind = "OpenCrafting", facilityId = "CityAlchemist" } } },
					{ text = "I'd like some potions.", actions = { { kind = "OpenShop", shop = "ApothecaryPotions" } } },
					{ text = "Another time." },
				},
			},
		},
	},

	-- The church: the player arrives through the Church's summoning circle; the priest explains in a few words and
	-- the System assigns a class (lore refinement, 2026-10-16; replaces the eighteenth-birthday awakening of L-43).
	PriestAwakening = {
		npc = "ChurchPriest",
		priority = 10,
		requires = { hasClass = false },
		journal = { title = "The Summoning", summary = "The Church's circle pulled me out of my own world and into this one. The System gave me a class." },
		nodes = {
			start = {
				lines = line(
					"Easy now. You were called here from another world by the Church's oldest rite.",
					"Rifts and monsters press on this realm. Those who answer the summoning are given the means to grow strong. The System will show you."
				),
				choices = {
					{ text = "Show me.", actions = { { kind = "Awaken" } }, next = "after" },
					{ text = "Give me a moment." },
				},
			},
			after = { lines = line("The System has chosen your path. There's a chest by the door with what you'll need, and the city square is just outside.") },
		},
	},
	PriestBlessing = {
		npc = "ChurchPriest",
		nodes = {
			start = {
				lines = line("Light keep you, adventurer."),
				choices = {
					{ text = "Do you need anything?", requires = { questAvailable = "HerbsForTheHealer" }, next = "herbs" },
					{ text = "I brought the herbs.", requires = { questReady = "HerbsForTheHealer" }, actions = { { kind = "TurnInQuest", questId = "HerbsForTheHealer" } }, next = "thanks" },
					{ text = "Goodbye." },
				},
			},
			herbs = {
				lines = line("The sick in the slums need more than prayers. Five healing herbs would ease a great deal of pain."),
				choices = {
					{ text = "I'll find some.", actions = { { kind = "AcceptQuest", questId = "HerbsForTheHealer" } } },
					{ text = "Not now." },
				},
			},
			thanks = { lines = line("Bless you. These will be a poultice before nightfall.") },
		},
	},

	-- The weary stranger on the church steps: the first quest (L-43). Nothing marks him as a quest giver.
	StrangerQuiet = {
		npc = "WearyStranger",
		nodes = { start = { lines = line("The bells are loud today. Someone's birthday, I'd wager.") } },
	},
	StrangerPlea = {
		npc = "WearyStranger",
		priority = 10,
		requires = { flag = "Awakened", questNotStarted = "TheStolenBelongings" },
		nodes = {
			start = {
				lines = line(
					"Spare a moment, friend? Not coin. Just a moment.",
					"Three of them came this morning. Took my blanket, my tools and my late wife's ring.",
					"They ran into the alley behind the church. I'm too old to follow, and the guards don't look twice at men like me."
				),
				choices = {
					{ text = "I'll get your things back.", actions = { { kind = "AcceptQuest", questId = "TheStolenBelongings" } }, next = "accepted" },
					{ text = "I can't right now." },
				},
			},
			accepted = { lines = line("Bless you. Mind yourself; they carry knives.") },
		},
	},
	StrangerWaiting = {
		npc = "WearyStranger",
		priority = 20,
		requires = { questActive = "TheStolenBelongings" },
		nodes = {
			start = {
				lines = line("Any sign of them?"),
				choices = {
					{ text = "Here are your things.", requires = { questReady = "TheStolenBelongings" }, actions = { { kind = "TurnInQuest", questId = "TheStolenBelongings" } }, next = "grateful" },
					{ text = "Not yet." },
				},
			},
			grateful = { lines = line(
				"Her ring... I thought I'd never hold it again.",
				"It isn't much, but take this. You've done more than the whole city guard."
			) },
		},
	},
	StrangerThanks = {
		npc = "WearyStranger",
		priority = 5,
		requires = { questCompleted = "TheStolenBelongings" },
		nodes = { start = { lines = line("I won't forget your kindness. If you hear of honest work for old hands, tell me.") } },
	},

	-- The hunter at the south gate: a side quest with a level requirement that is explained, not hidden
	HunterChat = {
		npc = "Hunter",
		nodes = { start = { lines = line("The forest road's been quiet. Too quiet, if you ask me.") } },
	},
	HunterTooSoon = {
		npc = "Hunter",
		priority = 9,
		requires = { questLevelTooLow = "HuntersRequest" },
		nodes = { start = { lines = line("I could use a hand with the wolves, but they'd tear you apart. Come back when you've reached level 2.") } },
	},
	HunterRequest = {
		npc = "Hunter",
		priority = 10,
		requires = { questAvailable = "HuntersRequest" },
		nodes = {
			start = {
				lines = line("You look able. The wolves along the forest road have grown bold. Four fewer would help."),
				choices = {
					{ text = "I'll hunt them.", actions = { { kind = "AcceptQuest", questId = "HuntersRequest" } } },
					{ text = "Another time." },
				},
			},
		},
	},
	HunterReport = {
		npc = "Hunter",
		priority = 20,
		requires = { questActive = "HuntersRequest" },
		nodes = {
			start = {
				lines = line("Well?"),
				choices = {
					{ text = "Four wolves fewer.", requires = { questReady = "HuntersRequest" }, actions = { { kind = "TurnInQuest", questId = "HuntersRequest" } } },
					{ text = "Still hunting." },
				},
			},
		},
	},

	-- Silk and Silver, the cosmetic shop (L-46)
	ClothierWares = {
		npc = "Clothier",
		nodes = {
			start = {
				lines = line("Silk and Silver, the finest finery in Lundand. None of it will save your life, mind. It only makes you look better while you risk it."),
				choices = {
					{ text = "Show me your wares.", actions = { { kind = "OpenShop", shop = "Cosmetics" } } },
					{ text = "Just admiring." },
				},
			},
		},
	},

	-- The inn
	InnRooms = {
		npc = "Innkeeper",
		nodes = {
			start = {
				lines = line("Warm beds, honest prices, and a lock on every door."),
				choices = {
					{ text = "I'd like a room.", actions = { { kind = "OpenRentals", innId = "SquareInn" } } },
					{ text = "Just looking." },
				},
			},
		},
	},
	-- Southern Woods quests (the Hunter)
	PeltsTooSoon = {
		npc = "Hunter",
		priority = 11,
		requires = { questLevelTooLow = "PeltsForTheHunter" },
		nodes = { start = { lines = line("There's more work, but you need a few more fights under your belt first.") } },
	},
	PeltsOffer = {
		npc = "Hunter",
		priority = 12,
		requires = { questAvailable = "PeltsForTheHunter" },
		nodes = {
			start = {
				lines = line("Winter's coming and my furs are thin. Bring me four wolf pelts and I'll make it worth your while."),
				choices = {
					{ text = "I'll bring the pelts.", actions = { { kind = "AcceptQuest", questId = "PeltsForTheHunter" } } },
					{ text = "Another time." },
				},
			},
		},
	},
	PeltsReport = {
		npc = "Hunter",
		priority = 21,
		requires = { questActive = "PeltsForTheHunter" },
		nodes = {
			start = {
				lines = line("Got those pelts?"),
				choices = {
					{ text = "Here are four pelts.", requires = { questReady = "PeltsForTheHunter" }, actions = { { kind = "TurnInQuest", questId = "PeltsForTheHunter" } } },
					{ text = "Not yet." },
				},
			},
		},
	},
	BoarsTooSoon = {
		npc = "Hunter",
		priority = 12,
		requires = { questLevelTooLow = "TheBoarProblem" },
		nodes = { start = { lines = line("The boars would gore you. Come back at level 3.") } },
	},
	BoarsOffer = {
		npc = "Hunter",
		priority = 13,
		requires = { questAvailable = "TheBoarProblem" },
		nodes = {
			start = {
				lines = line("Wild boars are ripping up the forest road. Put down three and the carts can pass again."),
				choices = {
					{ text = "I'll deal with the boars.", actions = { { kind = "AcceptQuest", questId = "TheBoarProblem" } } },
					{ text = "Another time." },
				},
			},
		},
	},
	BoarsReport = {
		npc = "Hunter",
		priority = 22,
		requires = { questActive = "TheBoarProblem" },
		nodes = {
			start = {
				lines = line("The boars?"),
				choices = {
					{ text = "Three boars, dealt with.", requires = { questReady = "TheBoarProblem" }, actions = { { kind = "TurnInQuest", questId = "TheBoarProblem" } } },
					{ text = "Not yet." },
				},
			},
		},
	},
	AlphaTooSoon = {
		npc = "Hunter",
		priority = 13,
		requires = { questLevelTooLow = "AlphaOfTheWoods" },
		nodes = { start = { lines = line("The Alpha would make a meal of you. Level 6, at least.") } },
	},
	AlphaOffer = {
		npc = "Hunter",
		priority = 14,
		requires = { questAvailable = "AlphaOfTheWoods" },
		nodes = {
			start = {
				lines = line("There's a great wolf with a den deep in the woods, east of the path. The packs answer to it. End it."),
				choices = {
					{ text = "I'll hunt the Alpha.", actions = { { kind = "AcceptQuest", questId = "AlphaOfTheWoods" } } },
					{ text = "Another time." },
				},
			},
		},
	},
	AlphaReport = {
		npc = "Hunter",
		priority = 23,
		requires = { questActive = "AlphaOfTheWoods" },
		nodes = {
			start = {
				lines = line("Is it done?"),
				choices = {
					{ text = "The Alpha is dead.", requires = { questReady = "AlphaOfTheWoods" }, actions = { { kind = "TurnInQuest", questId = "AlphaOfTheWoods" } } },
					{ text = "Not yet." },
				},
			},
		},
	},
	-- Hideout quests (rumours at the inn)
	ThugsTooSoon = {
		npc = "Innkeeper",
		priority = 14,
		requires = { questLevelTooLow = "TroubleInTheSlums" },
		nodes = { start = { lines = line("Bad business in the slums. Not for someone your level, though. Come back at level 4.") } },
	},
	ThugsOffer = {
		npc = "Innkeeper",
		priority = 15,
		requires = { questAvailable = "TroubleInTheSlums" },
		nodes = {
			start = {
				lines = line("You didn't hear it from me, but thugs are bleeding the slum folk dry. Someone ought to stop three of them."),
				choices = {
					{ text = "I'll stop them.", actions = { { kind = "AcceptQuest", questId = "TroubleInTheSlums" } } },
					{ text = "Another time." },
				},
			},
		},
	},
	ThugsReport = {
		npc = "Innkeeper",
		priority = 24,
		requires = { questActive = "TroubleInTheSlums" },
		nodes = {
			start = {
				lines = line("Any news from the slums?"),
				choices = {
					{ text = "Three thugs won't trouble anyone again.", requires = { questReady = "TroubleInTheSlums" }, actions = { { kind = "TurnInQuest", questId = "TroubleInTheSlums" } } },
					{ text = "Not yet." },
				},
			},
		},
	},
	EnforcerTooSoon = {
		npc = "Innkeeper",
		priority = 15,
		requires = { questLevelTooLow = "TheCellarGang" },
		nodes = { start = { lines = line("The one behind the thugs is dangerous. Get stronger first: level 9.") } },
	},
	EnforcerOffer = {
		npc = "Innkeeper",
		priority = 16,
		requires = { questAvailable = "TheCellarGang" },
		nodes = {
			start = {
				lines = line("Those thugs answer to an enforcer. Word is, there's a cellar door in a slum alley. He's down there."),
				choices = {
					{ text = "I'll find him.", actions = { { kind = "AcceptQuest", questId = "TheCellarGang" } } },
					{ text = "Another time." },
				},
			},
		},
	},
	EnforcerReport = {
		npc = "Innkeeper",
		priority = 25,
		requires = { questActive = "TheCellarGang" },
		nodes = {
			start = {
				lines = line("Well?"),
				choices = {
					{ text = "The enforcer is finished.", requires = { questReady = "TheCellarGang" }, actions = { { kind = "TurnInQuest", questId = "TheCellarGang" } } },
					{ text = "Not yet." },
				},
			},
		},
	},
	LeaderTooSoon = {
		npc = "Innkeeper",
		priority = 16,
		requires = { questLevelTooLow = "TheHideoutLeader" },
		nodes = { start = { lines = line("The leader of that place is no common thug. Come back at level 12.") } },
	},
	LeaderOffer = {
		npc = "Innkeeper",
		priority = 17,
		requires = { questAvailable = "TheHideoutLeader" },
		nodes = {
			start = {
				lines = line("With the enforcer gone, the one who runs that hideout will be furious. Finish this, and the slums can breathe."),
				choices = {
					{ text = "I'll end it.", actions = { { kind = "AcceptQuest", questId = "TheHideoutLeader" } } },
					{ text = "Another time." },
				},
			},
		},
	},
	LeaderReport = {
		npc = "Innkeeper",
		priority = 26,
		requires = { questActive = "TheHideoutLeader" },
		nodes = {
			start = {
				lines = line("Is it over?"),
				choices = {
					{ text = "The hideout leader is dead.", requires = { questReady = "TheHideoutLeader" }, actions = { { kind = "TurnInQuest", questId = "TheHideoutLeader" } } },
					{ text = "Not yet." },
				},
			},
		},
	},
})
