local randomStates = {
	"Tinkering...",
	"Brainstorming...",
	"Constructing...",
	"Blowing stuff up...",
	"Making stuff, twin...",
}

Presence.State = randomStates[math.random(#randomStates)]

local cover = PTImageAsset.New()
cover.ImageType = Enums.ImageType.PlaceIcon
cover.ImageID = 140234

Presence.CoverImage = cover

while wait(60) do
	Presence.State = randomStates[math.random(#randomStates)]
end
