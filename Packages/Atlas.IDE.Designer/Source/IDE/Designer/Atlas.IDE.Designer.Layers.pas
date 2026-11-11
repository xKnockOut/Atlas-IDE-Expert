unit Atlas.IDE.Designer.Layers;

// Ebenen im Designer schrittweise ordnen (#749) in der IDE: Untermenü „Ebene“
// im Menü „Anordnen“ und Strg+Bild auf/ab, solange der Designer den Fokus hat
// (TAtlasKeyHook, designer.zOrder.shortcuts). Die Rechnung macht
// TAtlasLayers unter den Geschwistern des markierten Steuerelements.
// - Eine Ebene nach vorn/hinten bezieht sich nur auf überlappende
//   Steuerelemente derselben Art (fensterlos oder fensterbehaftet); ganz nach
//   vorn/hinten an den Rand der eigenen Art. Die neue Reihenfolge setzt
//   BringToFront in Folge; das ändert auch die Reihenfolge in der DFM.
// - Stapel: alle Geschwister, die das markierte Steuerelement überlappen,
//   oberstes zuerst, mit Trennlinie vor den fensterlosen; mit
//   designer.zOrder.includeParents dahinter die Container-Vorfahren. Ein Klick
//   wählt das Steuerelement, auch wenn es verdeckt ist.
// - „Ebene rückgängig“ stellt die Reihenfolge vor dem letzten Schritt her.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Atlas.IDE.Foundation.KeyHook;

type
{$SCOPEDENUMS ON}
  TAtlasLayersCommand = (Forward, Backward, Front, Back, Undo);
{$SCOPEDENUMS OFF}

  TAtlasIdeDesignerLayers = class;

  /// <summary>Strg+Bild auf/ab, solange der Designer den Fokus hat.</summary>
  TAtlasDesignerLayerKeys = class(TAtlasKeyClient)
  private
    FOwner: TAtlasIdeDesignerLayers;
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  end;

  /// <summary>Ein Eintrag des Stapels: Name und ob davor eine Trennlinie steht.</summary>
  TAtlasStackEntry = record
    Name: string;
    Caption: string;
    Selected: Boolean;
    BreakBefore: Boolean;
  end;

  TAtlasIdeDesignerLayers = class
  private
    FOnMessage: TProc<string>;
    FKeys: TAtlasDesignerLayerKeys;
    /// <summary>Stand vor dem letzten Schritt: Datei, Parent (leer = Formular) und Namen von unten nach oben.
    /// </summary>
    FUndoFile: string;
    FUndoParent: string;
    FUndoOrder: TArray<string>;
    procedure Say(const AText: string);
    procedure Reorder(ACommand: TAtlasLayersCommand);
    procedure Restore;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    procedure UpdateKeys(AWanted: Boolean);
    procedure Execute(ACommand: TAtlasLayersCommand);
    function CanUndo: Boolean;
    /// <summary>Genau ein Steuerelement mit Parent markiert?</summary>
    class function HasTarget: Boolean; static;
    /// <summary>Stapel um das markierte Steuerelement (oberstes zuerst), samt Vorfahren nach Einstellung.</summary>
    class function Stack: TArray<TAtlasStackEntry>; static;
    /// <summary>Steuerelement AName im aktiven Designer auswählen.</summary>
    class procedure SelectName(const AName: string); static;
  end;

implementation

uses
  Winapi.Windows,
  System.Types,
  ToolsAPI,
  Atlas.Core.Designer.Layers,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.Settings;

const
  cKeyPriority = 50;

/// <summary>Das eine markierte Steuerelement mit Parent; False sonst.</summary>
function Target(out AEditor: IOTAFormEditor; out ARoot: TComponent; out AControl: TControl): Boolean;
var
  mSelected: TArray<TComponent>;
begin
  AControl := nil;
  Result := TAtlasIdeSettings.Current.DesignerZOrder and TAtlasDesignerAccess.Current(AEditor, ARoot);
  if not Result then
  begin
    Exit;
  end;
  mSelected := TAtlasDesignerAccess.Selection(AEditor, ARoot);
  Result := (Length(mSelected) = 1) and (mSelected[0] is TControl) and (TControl(mSelected[0]).Parent <> nil);
  if Result then
  begin
    AControl := TControl(mSelected[0]);
  end;
end;

/// <summary>Geschwister in der Reihenfolge des Parents, von unten nach oben.</summary>
function SiblingsOf(AParent: TWinControl): TArray<TControl>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AParent.ControlCount - 1 do
  begin
    Result := Result + [AParent.Controls[mIndex]];
  end;
end;

function ItemsOf(const AControls: TArray<TControl>): TArray<TAtlasLayerItem>;
var
  mControl: TControl;
begin
  Result := nil;
  for mControl in AControls do
  begin
    Result := Result + [TAtlasLayerItem.Create(mControl.Name, mControl.BoundsRect, mControl is TWinControl)];
  end;
end;

function IndexIn(const AControls: TArray<TControl>; AControl: TControl): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(AControls) do
  begin
    if AControls[mIndex] = AControl then
    begin
      Exit(mIndex);
    end;
  end;
end;

function ParentKey(AControl: TControl; ARoot: TComponent): string;
begin
  Result := '';
  if AControl.Parent <> ARoot then
  begin
    Result := AControl.Parent.Name;
  end;
end;

{ TAtlasDesignerLayerKeys }

function TAtlasDesignerLayerKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.DesignerZOrder and mSettings.DesignerZOrderShortcuts and (AShift = [ssCtrl]) and
    ((AKey = VK_PRIOR) or (AKey = VK_NEXT)) and TAtlasDesignerAccess.Focused;
end;

procedure TAtlasDesignerLayerKeys.HandleKey(AKey: Word; AShift: TShiftState);
var
  mOwner: TAtlasIdeDesignerLayers;
  mForward: Boolean;
begin
  mOwner := FOwner;
  mForward := AKey = VK_PRIOR;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      if mForward then
      begin
        mOwner.Execute(TAtlasLayersCommand.Forward);
      end
      else
      begin
        mOwner.Execute(TAtlasLayersCommand.Backward);
      end;
    end);
end;

{ TAtlasIdeDesignerLayers }

constructor TAtlasIdeDesignerLayers.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FKeys := TAtlasDesignerLayerKeys.Create(cKeyPriority);
  FKeys.FOwner := Self;
end;

destructor TAtlasIdeDesignerLayers.Destroy;
begin
  if FKeys <> nil then
  begin
    TAtlasKeyHook.Remove(FKeys);
    FKeys.Free;
  end;
  inherited Destroy;
end;

procedure TAtlasIdeDesignerLayers.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

procedure TAtlasIdeDesignerLayers.UpdateKeys(AWanted: Boolean);
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  if AWanted and mSettings.DesignerZOrder and mSettings.DesignerZOrderShortcuts then
  begin
    TAtlasKeyHook.Add(FKeys);
  end
  else
  begin
    TAtlasKeyHook.Remove(FKeys);
  end;
end;

class function TAtlasIdeDesignerLayers.HasTarget: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mControl: TControl;
begin
  Result := Target(mEditor, mRoot, mControl);
end;

function NewOrder(const AItems: TArray<TAtlasLayerItem>; AIndex: Integer;
  ACommand: TAtlasLayersCommand): TArray<Integer>;
begin
  case ACommand of
    TAtlasLayersCommand.Forward:
      Result := TAtlasLayers.Step(AItems, AIndex, True);
    TAtlasLayersCommand.Backward:
      Result := TAtlasLayers.Step(AItems, AIndex, False);
    TAtlasLayersCommand.Front:
      Result := TAtlasLayers.Extreme(AItems, AIndex, True);
  else
    Result := TAtlasLayers.Extreme(AItems, AIndex, False);
  end;
end;

procedure TAtlasIdeDesignerLayers.Reorder(ACommand: TAtlasLayersCommand);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mControl: TControl;
  mSiblings: TArray<TControl>;
  mOrder: TArray<Integer>;
  mIndex: Integer;
  mWindowed: Boolean;
begin
  if not Target(mEditor, mRoot, mControl) or (TAtlasDesignerAccess.DesignerOf(mEditor) = nil) then
  begin
    Exit;
  end;
  mSiblings := SiblingsOf(mControl.Parent);
  mOrder := NewOrder(ItemsOf(mSiblings), IndexIn(mSiblings, mControl), ACommand);
  if Length(mOrder) = 0 then
  begin
    Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerLayerNone, [mControl.Name]));
    Exit;
  end;
  FUndoFile := mEditor.FileName;
  FUndoParent := ParentKey(mControl, mRoot);
  FUndoOrder := nil;
  for mIndex := 0 to High(mSiblings) do
  begin
    FUndoOrder := FUndoOrder + [mSiblings[mIndex].Name];
  end;
  // BringToFront in der neuen Folge, nur für die eigene Art: Die andere Liste des Parents bleibt.
  mWindowed := mControl is TWinControl;
  for mIndex in mOrder do
  begin
    if (mSiblings[mIndex] is TWinControl) = mWindowed then
    begin
      mSiblings[mIndex].BringToFront;
    end;
  end;
  TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerLayerDone, [mControl.Name]));
end;

function TAtlasIdeDesignerLayers.CanUndo: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := (FUndoFile <> '') and TAtlasDesignerAccess.Current(mEditor, mRoot) and
    SameText(mEditor.FileName, FUndoFile);
end;

procedure TAtlasIdeDesignerLayers.Restore;
var
  mEditor: IOTAFormEditor;
  mRoot, mParent, mComponent: TComponent;
  mName: string;
begin
  if not CanUndo or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mParent := mRoot;
  if FUndoParent <> '' then
  begin
    mParent := mRoot.FindComponent(FUndoParent);
  end;
  if mParent is TWinControl then
  begin
    for mName in FUndoOrder do
    begin
      mComponent := mRoot.FindComponent(mName);
      if (mName <> '') and (mComponent is TControl) and (TControl(mComponent).Parent = mParent) then
      begin
        TControl(mComponent).BringToFront;
      end;
    end;
  end;
  FUndoFile := '';
  FUndoOrder := nil;
  if TAtlasDesignerAccess.DesignerOf(mEditor) <> nil then
  begin
    TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  end;
  Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerLayerUndone));
end;

procedure TAtlasIdeDesignerLayers.Execute(ACommand: TAtlasLayersCommand);
begin
  if ACommand = TAtlasLayersCommand.Undo then
  begin
    Restore;
  end
  else
  begin
    Reorder(ACommand);
  end;
end;

function EntryOf(AControl: TControl; ASelected, ABreak: Boolean): TAtlasStackEntry;
begin
  Result.Name := AControl.Name;
  Result.Caption := AControl.Name + ' (' + AControl.ClassName + ')';
  Result.Selected := ASelected;
  Result.BreakBefore := ABreak;
end;

class function TAtlasIdeDesignerLayers.Stack: TArray<TAtlasStackEntry>;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mControl: TControl;
  mSiblings: TArray<TControl>;
  mIndex: Integer;
  mWindowed: Boolean;
  mParent: TWinControl;
begin
  Result := nil;
  if not Target(mEditor, mRoot, mControl) then
  begin
    Exit;
  end;
  mSiblings := SiblingsOf(mControl.Parent);
  mWindowed := True;
  for mIndex in TAtlasLayers.Stack(ItemsOf(mSiblings), mControl.BoundsRect) do
  begin
    // Trennlinie vor dem ersten fensterlosen: Die liegen immer darunter.
    Result := Result + [EntryOf(mSiblings[mIndex], mSiblings[mIndex] = mControl,
      mWindowed and not (mSiblings[mIndex] is TWinControl) and (Length(Result) > 0))];
    mWindowed := mSiblings[mIndex] is TWinControl;
  end;
  if not TAtlasIdeSettings.Current.DesignerZOrderIncludeParents then
  begin
    Exit;
  end;
  // Vorfahren nach einer Trennlinie, der nächste zuerst.
  mParent := mControl.Parent;
  mWindowed := True;
  while (mParent <> nil) and (mParent <> mRoot) do
  begin
    Result := Result + [EntryOf(mParent, False, mWindowed)];
    mWindowed := False;
    mParent := mParent.Parent;
  end;
end;

class procedure TAtlasIdeDesignerLayers.SelectName(const AName: string);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) or (TAtlasDesignerAccess.DesignerOf(mEditor) = nil) then
  begin
    Exit;
  end;
  mComponent := mRoot.FindComponent(AName);
  if mComponent <> nil then
  begin
    TAtlasDesignerAccess.Select(TAtlasDesignerAccess.DesignerOf(mEditor), mRoot, [mComponent]);
  end;
end;

end.
