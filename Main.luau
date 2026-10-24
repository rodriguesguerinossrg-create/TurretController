-- nyro_dev (On Discord) && UsuarioRealMesmo (On Roblox)

-- Constants

const TweenService = game:GetService("TweenService") -- Used for the beam fade
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const Debris = game:GetService("Debris")

const Assets = ReplicatedStorage:WaitForChild("Assets")
const BulletHoleTemplate = Assets:WaitForChild("BulletHole") :: BasePart

const TurretModel = script.Parent :: Model -- The turret model is the script's parent
const TurretHead = TurretModel:WaitForChild("TurretHead", 15) :: Model

const Highlight = TurretModel:WaitForChild("Highlight") :: Highlight -- Shows the stress level

const FireParticles = TurretHead:WaitForChild("Minigun"):WaitForChild("Fire") -- Particles at the barrel

const HeadRoot = TurretHead:WaitForChild("Root", 15) :: BasePart
const ModelRoot = TurretModel:WaitForChild("Root", 15) :: BasePart

const DisableTurretClicker = ModelRoot:WaitForChild("Click") :: ClickDetector

const OriginBeam = HeadRoot.Origin -- Origin of the red laser beam
const EndBeam = HeadRoot.End -- End of the red laser beam

const RunService = game:GetService("RunService")
const PlayerService = game:GetService("Players")
const LocalPlayer = PlayerService.LocalPlayer

-- >> Settings

const DebrisFolder = workspace -- Folder where the beams, attachments and bullet holes are created. You can change it to any folder you want
const ShootRandomDirection = 3 -- Random spread applied to each bullet's direction

const DamagePerBulletFired = 1 -- Damage dealt per bullet
const ShootingDistanceLimit = 40 -- If your character is farther than this, the turret stops shooting

const HeadRotationVelocity = 5 -- How fast the turret head turns
const HeadRotationLerping = 10 -- How fast the head smoothly interpolates toward the target rotation

const HeadExplosionRandomForce = 40 -- How random the head explosion velocity is on every axis
const HeadExplosionForce = 120 -- How much upward force is applied to the head when it explodes

const BulletHoleDestroyingTime = 20 -- How long the bullet hole stays in the workspace

const FollowDebounceTime = 1 -- After the follow debounce is set to true, it waits 1 second before setting it back to false

const RayParams = RaycastParams.new() -- Raycast filter. Change it if you want the turret to stop shooting other things
RayParams.FilterType = Enum.RaycastFilterType.Exclude -- Excludes the FilterDescendantsInstances list from the raycast
RayParams.FilterDescendantsInstances = {TurretModel} -- Ignores the turret model

const ShootingBeamColor = ColorSequence.new(Color3.new(1, 0.627451, 0.0313725)) -- Color of the shooting beam effect. Change it if you want

-- >> Variables

local CurrentCharacter = nil :: Model -- Your character in the game
local CurrentHumanoid = nil :: Humanoid -- Your character's Humanoid (if loaded)

local LookTarget = HeadRoot.CFrame :: CFrame -- Turret head rotation target

local DiffNumber = 1 -- Direction of the Y axis rotation: 1 turns one way, -1 turns the other way
local FollowTarget = false :: boolean -- When true, the turret follows your character

local FollowDebounce = false :: boolean -- When true, the turret is in cooldown and won't start following the character
local Shooting = false :: boolean -- When true, the turret keeps shooting

local StressLevel = 0 -- Increases with each bullet, decreases when not shooting
local StressLimit = 500 -- When the stress level passes this, the turret stops shooting

local IsStressed = false -- True while the turret is overheated
local IsEnabled = true -- Set to false when you click the turret (ModelRoot), which disables it

-- Called when your character is loaded
const function OnCharacterAdded(NewCharacter: Model) : never
	if not NewCharacter or not NewCharacter.Parent then return end -- Ignores it if your character doesn't exist

	-- CharacterAdded fires on every spawn, so the target updates to the new character
	CurrentCharacter = NewCharacter -- The turret only tracks the local player, which is safe because this is a LocalScript
	CurrentHumanoid = NewCharacter:WaitForChild("Humanoid")

	local HealthChangedConnection
	HealthChangedConnection = CurrentHumanoid.HealthChanged:Connect(function(health: number)
		if health > 0 then return end

		HealthChangedConnection:Disconnect()
		Shooting = false
		CurrentHumanoid = nil
		CurrentCharacter = nil
		FollowTarget = false
	end)
end

-- Checks if the character is in front of the turret
const function IsCharacterOnSight() : boolean
	-- Raycast forward from the head to see if it hits your character
	const Raycast = workspace:Raycast(HeadRoot.Position, HeadRoot.CFrame.LookVector * ShootingDistanceLimit, RayParams)
	return Raycast ~= nil and Raycast.Instance.Parent == CurrentCharacter
end

-- Emits every ParticleEmitter inside an object, using either the given emitCount or the "EmitCount" attribute
const function EmitParticles(object: Instance | Attachment, emitCount: number) : never
	for _, particle in object:QueryDescendants("ParticleEmitter") do -- Goes through every ParticleEmitter in the object
		particle:Emit(emitCount or particle:GetAttribute("EmitCount")) -- Emits using emitCount, or the attribute if emitCount is nil
	end
end

-- Creates a raycast in the turret's looking direction. If your character is in front of it, the turret deals damage
const function FireBullet() : never
	-- Attachments that the beam uses as start and end points
	const OriginPointAttach = Instance.new("Attachment", DebrisFolder)
	const ShootPointAttach = Instance.new("Attachment", DebrisFolder)
	OriginPointAttach.Position = FireParticles.WorldPosition -- The origin of the visual is at the FireParticles position

	const ShootBeam = Instance.new("Beam", HeadRoot) -- The beam line
	ShootBeam.Attachment0 = OriginPointAttach
	ShootBeam.Attachment1 = ShootPointAttach
	ShootBeam.Width0 = .1
	ShootBeam.Width1 = .1
	ShootBeam.Color = ShootingBeamColor
	ShootBeam.LightEmission = 10
	ShootBeam.FaceCamera = true

	const Tween = TweenService:Create(ShootBeam, TweenInfo.new(.15), {Width1 = 0}) -- Fade-out effect for the beam
	Tween:Play()

	Tween.Completed:Connect(function() -- Destroys the beam and its attachments after the fade-out
		ShootBeam:Destroy()
		OriginPointAttach:Destroy()
		ShootPointAttach:Destroy()
	end)

	-- Random spread so the bullets don't all go the same way
	const RandomVector = Vector3.new(math.random(-ShootRandomDirection, ShootRandomDirection), math.random(-ShootRandomDirection, ShootRandomDirection), math.random(-ShootRandomDirection, ShootRandomDirection))
	const LookCF = HeadRoot.CFrame
	const Raycast = workspace:Raycast(LookTarget.Position, LookCF.LookVector * ShootingDistanceLimit + RandomVector, RayParams) -- Ignores the turret model and the other objects in the filter list

	if Raycast then
		const Instance = Raycast.Instance
		ShootPointAttach.Position = Raycast.Position -- The end of the beam goes to the hit position
		if CurrentCharacter and CurrentCharacter.PrimaryPart and Raycast.Instance.Parent == CurrentCharacter then
			CurrentHumanoid:TakeDamage(DamagePerBulletFired) -- Damages the Humanoid
		elseif not Instance.Parent:IsA("Accessory") then
			const Offset = CFrame.new(Instance.Position, Instance.Position + Raycast.Normal) -- Gets the rotation from the raycast normal

			const BulletHole = BulletHoleTemplate:Clone() -- Creates a bullet hole decal
			BulletHole.CFrame = CFrame.new(Raycast.Position) * Offset.Rotation * CFrame.Angles(math.rad(-90), 0, 0)
			BulletHole.Parent = DebrisFolder

			Debris:AddItem(BulletHole, BulletHoleDestroyingTime) -- Destroys the bullet hole after BulletHoleDestroyingTime seconds
		end
	else
		ShootPointAttach.Position = LookTarget.Position + (LookCF.LookVector * ShootingDistanceLimit + RandomVector) -- The end of the beam goes to the max distance
	end
end

-- Loops, calling FireBullet every 0.05 seconds, and adds stress to the turret
-- If the turret is stressed, it stops shooting
const function StartShooting()
	if Shooting then return end -- Checks if the turret is already shooting
	Shooting = true -- Marks the turret as shooting

	local t = os.clock() -- Saves the time of the last shot

	while Shooting and IsEnabled do -- Fires a bullet every 0.05 seconds
		const dt = os.clock() - t -- Time since the last shot
		t = os.clock()

		if IsStressed then task.wait() continue end -- Skips shooting while overheated

		EmitParticles(FireParticles, 1) -- Emits the front fire particles
		FireBullet() -- Fires a bullet raycast

		StressLevel += dt * 100 -- Stress builds up while shooting
		if StressLevel > StressLimit then -- If the stress level is over the limit, marks the turret as stressed
			IsStressed = true
			StressLevel = StressLimit -- Keeps the stress from going over the limit
		end

		task.wait(.05) -- Waits 0.05 seconds before the next bullet
	end
end

const Connections = {}

-- Runs every rendered frame
const function OnRenderStepped(deltaTime: number)
	const CharacterPrimaryPart = CurrentCharacter and CurrentCharacter.PrimaryPart
	const CharacterDistance = CharacterPrimaryPart and (CharacterPrimaryPart.Position - HeadRoot.Position).Magnitude

	if not IsEnabled then
		const CurrentHeadCF = TurretHead:GetPivot()
		const Alpha = 1 - math.exp(-4 * deltaTime)

		TurretHead:PivotTo(
			CurrentHeadCF:Lerp(CFrame.new(CurrentHeadCF.Position) * CFrame.Angles(math.rad(90), 0, math.rad(90)), Alpha))

		return
	end

	Highlight.FillTransparency = 1 - StressLevel / StressLimit -- More stress, more visible highlight

	-- Cools down when not shooting or when stressed
	if (not Shooting or IsStressed) and StressLevel > 0 then
		StressLevel -= deltaTime * 100

		if StressLevel <= 0 then
			IsStressed = false
			StressLevel = 0
		end
	end

	-- Checks if your character exists and how far it is from the shooting limit
	if not CharacterPrimaryPart or CharacterDistance > ShootingDistanceLimit then
		FollowTarget = false -- Stops following the character
		Shooting = false -- Stops shooting bullets
	end

	-- Only starts following if the debounce is over, the character is within range, and the turret can see the character
	if not FollowDebounce
		and not FollowTarget -- Checks if it's not already following the character
		and CharacterPrimaryPart -- Checks if the character exists
		and CharacterDistance <= ShootingDistanceLimit -- Checks if the character is within the shooting limit
		and IsCharacterOnSight() then -- Checks if the turret can see the character

		task.spawn(StartShooting) -- Spawns a thread so the shooting loop doesn't block this frame
		FollowTarget = true -- Starts following the character
	end

	if not FollowTarget then
		-- Automatic head rotation (Y axis only)
		const _, Y = LookTarget:ToOrientation()
		LookTarget = CFrame.new(LookTarget.Position) * CFrame.Angles(0, Y + math.rad(deltaTime * HeadRotationVelocity * 10 * DiffNumber), 0)

	elseif CharacterPrimaryPart then -- If the character exists
		-- Follows the local character
		LookTarget = CFrame.new(LookTarget.Position, CharacterPrimaryPart.Position)
	end

	-- Checks the yaw again with the new target to see if it went past the limit
	const RelativeRotation = ModelRoot.CFrame:ToObjectSpace(LookTarget)
	const _, YAxis = RelativeRotation:ToOrientation()
	--const YAxis = math.atan2(-RelativeRotation.LookVector.X, -RelativeRotation.LookVector.Z)

	if math.abs(YAxis) > math.rad(90) then

		-- Only starts the cooldown if it was following and no cooldown is running
		if FollowTarget and not FollowDebounce then
			Shooting = false -- Stops shooting bullets
			FollowDebounce = true

			task.delay(FollowDebounceTime, function() FollowDebounce = false end)
		end

		FollowTarget = false -- Went past the limit, so always drop the target

		if YAxis * DiffNumber > 0 then -- Reverses direction only if it's going outside the limit
			DiffNumber *= -1
		end
	end

	-- Smoothly interpolates the head rotation toward LookTarget
	const CurrentHeadCF = TurretHead:GetPivot()
	const Alpha = 1 - math.exp(-HeadRotationLerping * deltaTime)
	TurretHead:PivotTo(CurrentHeadCF:Lerp(LookTarget, Alpha))
end

OnCharacterAdded(LocalPlayer.Character) -- Checks if your character has already loaded

table.insert(Connections, LocalPlayer.CharacterAdded:Connect(OnCharacterAdded)) -- Connects the character spawn event
table.insert(Connections, RunService.RenderStepped:Connect(OnRenderStepped)) -- Runs the turret logic every frame

table.insert(Connections, DisableTurretClicker.MouseClick:Connect(function()
	if not IsStressed then return end -- The turret can only be disabled if it's stressed
	if not IsEnabled then return end

	ModelRoot.CanCollide = false
	IsEnabled = false -- Starts the "disabled" animation

	TweenService:Create(Highlight, TweenInfo.new(.5), {
		FillTransparency = 1 -- Removes the red highlight
	}):Play()

	HeadRoot.Origin.Beam.Enabled = false -- Removes the beam once disabled

	task.wait(1) -- Waits 1 second

	EmitParticles(ModelRoot.Attachment, 1) -- Emits the explosion effect particles

	for _, part in TurretHead:QueryDescendants("BasePart") do -- Goes through every part of the turret head
		part.Anchored = false -- Applies physics by removing the anchor
	end

	const RandomVelocity = Vector3.new( -- Random velocity on every axis
		math.random(-HeadExplosionRandomForce, HeadExplosionRandomForce),
		math.random(-HeadExplosionRandomForce, HeadExplosionRandomForce),
		math.random(-HeadExplosionRandomForce, HeadExplosionRandomForce)
	)

	HeadRoot:ApplyImpulse( -- Launches the head upward with the explosion
		Vector3.yAxis * HeadRoot.Mass * HeadExplosionForce + RandomVelocity)

	HeadRoot.AssemblyAngularVelocity = RandomVelocity -- Applies a random angular velocity

	for _, con in Connections do -- Goes through every connection
		con:Disconnect() -- Disconnects it permanently
	end
end))
