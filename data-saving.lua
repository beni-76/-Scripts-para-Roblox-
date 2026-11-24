--[[
	DragDropController (ModuleScript, hijo de InventoryClient)

	Gestiona el arrastre de ítems entre slots (mouse y touch):
	  1. Presionar sobre un slot con ítem -> aparece un "fantasma" que sigue al puntero
	  2. Soltar sobre otro slot            -> llama a onDrop(fromSlot, toSlot)

	No modifica el inventario: solo notifica la intención. El servidor decide
	y la UI se actualiza cuando llega el Sync.
]]

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local DragDropController = {}
DragDropController.__index = DragDropController

-- ============================================================
-- Helpers
-- ============================================================

local function isPrimaryPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

--- Posición del puntero en coordenadas REALES de pantalla (las mismas que
--- AbsolutePosition cuando el ScreenGui usa IgnoreGuiInset = true).
--- Mouse: GetMouseLocation ya las devuelve así.
--- Touch: input.Position excluye la barra superior, hay que sumarla.
local function getPointerPosition(input: InputObject): Vector2
	if input.UserInputType == Enum.UserInputType.Touch then
		return Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
	end
	return UserInputService:GetMouseLocation()
end

-- ============================================================
-- Constructor
-- ============================================================

--- @param ui instancia de InventoryUI
--- @param onDrop función (fromSlot: number, toSlot: number) -> () llamada al soltar sobre otro slot
function DragDropController.new(ui, onDrop: (number, number) -> ())
	local self = setmetatable({}, DragDropController)

	self._ui = ui
	self._onDrop = onDrop
	self._connections = {}
	self._drag = nil -- { FromSlot, Ghost, InputType } mientras se arrastra

	return self
end

-- ============================================================
-- API pública
-- ============================================================

--- Conecta los eventos de input. Llamar una sola vez.
function DragDropController:Start()
	-- Inicio del arrastre: un listener por slot
	for index, slotFrame in ipairs(self._ui:GetSlotFrames()) do
		table.insert(self._connections, slotFrame.InputBegan:Connect(function(input)
			if isPrimaryPress(input) then
				self:_beginDrag(index, input)
			end
		end))
	end

	-- Movimiento y fin del arrastre: globales
	table.insert(self._connections, UserInputService.InputChanged:Connect(function(input)
		self:_onInputChanged(input)
	end))
	table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
		self:_onInputEnded(input)
	end))
end

--- Cancela el arrastre actual (si lo hay) sin enviar nada al servidor.
function DragDropController:Cancel()
	local drag = self._drag
	if not drag then
		return
	end

	self._drag = nil
	drag.Ghost:Destroy()
	self._ui:SetSlotDimmed(drag.FromSlot, false)
end

--- Desconecta todo y libera recursos.
function DragDropController:Destroy()
	self:Cancel()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

-- ============================================================
-- Privado
-- ============================================================

function DragDropController:_beginDrag(index: number, input: InputObject)
	-- Ignorar si ya hay un drag o el slot está vacío
	if self._drag or not self._ui:HasItem(index) then
		return
	end

	-- El fantasma se crea ANTES de atenuar el original para que no herede la transparencia
	local ghost = self._ui:CreateGhost(index)
	self._ui:SetSlotDimmed(index, true)

	self._drag = {
		FromSlot = index,
		Ghost = ghost,
		InputType = input.UserInputType,
	}
	self:_moveGhost(getPointerPosition(input))
end

function DragDropController:_moveGhost(position: Vector2)
	if self._drag then
		self._drag.Ghost.Position = UDim2.fromOffset(position.X, position.Y)
	end
end

function DragDropController:_onInputChanged(input: InputObject)
	if not self._drag then
		return
	end

	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseMovement or inputType == Enum.UserInputType.Touch then
		self:_moveGhost(getPointerPosition(input))
	end
end

function DragDropController:_onInputEnded(input: InputObject)
	local drag = self._drag
	if not drag or input.UserInputType ~= drag.InputType then
		return
	end

	local fromSlot = drag.FromSlot
	local toSlot = self._ui:GetSlotAt(getPointerPosition(input))

	self:Cancel() -- limpia fantasma y atenuado

	if toSlot and toSlot ~= fromSlot then
		self._onDrop(fromSlot, toSlot)
	end
end

return DragDropController
