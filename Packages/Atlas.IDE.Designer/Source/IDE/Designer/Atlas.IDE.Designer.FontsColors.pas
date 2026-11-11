unit Atlas.IDE.Designer.FontsColors;

// Befehl „Schriften und Farben …“ (#741) im Menü „Anordnen“ in der IDE:
// liest Font, ParentFont, Color und ParentColor aller Komponenten des
// Formulars über RTTI, zeigt Gruppen und Ausreißer (TAtlasFontsColors,
// TAtlasFontsDialog) und ersetzt nach Vorschau. Ein Klick auf eine Zeile
// wählt die Komponenten im Designer. Font.Height folgt der Designgröße des
// Formulars (PixelsPerInch). Farben ersetzen gilt für Color und Font.Color.
// „Schriften rückgängig“ stellt den Stand vor dem letzten Ersetzen her.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  ToolsAPI,
  Atlas.Core.Designer.FontsColors;

type
  /// <summary>Stand einer Komponente vor dem Ersetzen.</summary>
  TAtlasFontState = record
    Component: string;
    FontName: string;
    FontHeight: Integer;
    FontStyle: TFontStyles;
    FontColor: TColor;
    ParentFont: Boolean;
    Color: TColor;
    ParentColor: Boolean;
  end;

  TAtlasIdeFontsColors = class
  private
    FOnMessage: TProc<string>;
    FUndoFile: string;
    FUndo: TArray<TAtlasFontState>;
    procedure Say(const AText: string);
    procedure Remember(const AEditor: IOTAFormEditor; ARoot: TComponent; const ANames: TArray<string>);
    procedure ReplaceFont(const AEditor: IOTAFormEditor; ARoot: TComponent; const AUses: TArray<TAtlasFontUse>;
      const ARow: TAtlasFontRow; const AOthers: TArray<TAtlasFontRow>);
    procedure ReplaceColor(const AEditor: IOTAFormEditor; ARoot: TComponent; const AUses: TArray<TAtlasFontUse>;
      const ARow: TAtlasColorRow; const AOthers: TArray<TAtlasColorRow>);
    procedure Apply(const AEditor: IOTAFormEditor; ARoot: TComponent; const AFonts: TArray<TAtlasFontChange>;
      const AColors: TArray<TAtlasColorChange>);
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    procedure Execute;
    function CanUndo: Boolean;
    procedure Undo;
  end;

implementation

uses
  System.StrUtils,
  System.TypInfo,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Dialogs,
  DesignIntf,
  Atlas.UI.Designer.Strings,
  Atlas.UI.Designer.FontsDialog,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.Settings;

const
  cDefaultPixelsPerInch = 96;
  cMaxPreviewLines = 15;
  cAllParts = [TAtlasFontPart.Name, TAtlasFontPart.Size, TAtlasFontPart.Style, TAtlasFontPart.Color];

{ RTTI }

function FontOfComponent(AComponent: TComponent): TFont;
begin
  Result := nil;
  if (AComponent <> nil) and IsPublishedProp(AComponent, 'Font') and (PropType(AComponent, 'Font') = tkClass) and
    (GetObjectProp(AComponent, 'Font') is TFont) then
  begin
    Result := TFont(GetObjectProp(AComponent, 'Font'));
  end;
end;

function FlagOf(AComponent: TComponent; const AName: string): Boolean;
begin
  Result := IsPublishedProp(AComponent, AName) and (PropType(AComponent, AName) = tkEnumeration) and
    (GetOrdProp(AComponent, AName) <> 0);
end;

procedure SetFlag(AComponent: TComponent; const AName: string; AValue: Boolean);
begin
  if IsPublishedProp(AComponent, AName) and (PropType(AComponent, AName) = tkEnumeration) then
  begin
    SetOrdProp(AComponent, AName, Ord(AValue));
  end;
end;

function HasColor(AComponent: TComponent): Boolean;
begin
  Result := IsPublishedProp(AComponent, 'Color') and (PropType(AComponent, 'Color') = tkInteger);
end;

function ParentNameOf(AComponent, ARoot: TComponent): string;
var
  mParent: TWinControl;
begin
  Result := '';
  if (AComponent <> ARoot) and (AComponent is TControl) then
  begin
    mParent := TControl(AComponent).Parent;
    if (mParent = ARoot) or ((mParent <> nil) and (mParent.Owner = ARoot)) then
    begin
      Result := mParent.Name;
    end;
  end;
end;

function UseOf(AComponent, ARoot: TComponent): TAtlasFontUse;
begin
  Result := Default(TAtlasFontUse);
  Result.Component := AComponent.Name;
  Result.ParentName := ParentNameOf(AComponent, ARoot);
  Result.Font := TAtlasFontsDialog.KeyOf(FontOfComponent(AComponent));
  Result.ParentFont := FlagOf(AComponent, 'ParentFont');
  Result.HasColor := HasColor(AComponent);
  if Result.HasColor then
  begin
    Result.Color := ColorToString(TColor(GetOrdProp(AComponent, 'Color')));
    Result.ParentColor := FlagOf(AComponent, 'ParentColor');
  end;
end;

function Collect(ARoot: TComponent): TArray<TAtlasFontUse>;
var
  mIndex: Integer;
begin
  Result := nil;
  if FontOfComponent(ARoot) <> nil then
  begin
    Result := [UseOf(ARoot, ARoot)];
  end;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    if FontOfComponent(ARoot.Components[mIndex]) <> nil then
    begin
      Result := Result + [UseOf(ARoot.Components[mIndex], ARoot)];
    end;
  end;
end;

function Find(ARoot: TComponent; const AName: string): TComponent;
begin
  Result := ARoot;
  if not SameText(ARoot.Name, AName) then
  begin
    Result := ARoot.FindComponent(AName);
  end;
end;

function PixelsPerInchOf(ARoot: TComponent): Integer;
begin
  Result := cDefaultPixelsPerInch;
  if IsPublishedProp(ARoot, 'PixelsPerInch') then
  begin
    Result := GetOrdProp(ARoot, 'PixelsPerInch');
  end;
end;

function SelectedNames(const AEditor: IOTAFormEditor; ARoot: TComponent): TArray<string>;
var
  mComponent: TComponent;
begin
  Result := nil;
  for mComponent in TAtlasDesignerAccess.Selection(AEditor, ARoot) do
  begin
    Result := Result + [mComponent.Name];
  end;
end;

function ChangedNames(const AFonts: TArray<TAtlasFontChange>; const AColors: TArray<TAtlasColorChange>): TArray<string>;
var
  mFont: TAtlasFontChange;
  mColor: TAtlasColorChange;
begin
  Result := nil;
  for mFont in AFonts do
  begin
    Result := Result + [mFont.Component];
  end;
  for mColor in AColors do
  begin
    Result := Result + [mColor.Component];
  end;
end;

/// <summary>Vorschau der Änderungen; True, wenn übernommen werden soll.</summary>
function Confirm(const AFonts: TArray<TAtlasFontChange>; const AColors: TArray<TAtlasColorChange>): Boolean;
var
  mLines: string;
  mCount: Integer;
  mFont: TAtlasFontChange;
  mColor: TAtlasColorChange;

  procedure Line(const AComponent, AValue: string; AToParent: Boolean);
  begin
    Inc(mCount);
    if mCount <= cMaxPreviewLines then
    begin
      mLines := mLines + sLineBreak + AComponent + ': ' + AValue;
      if AToParent then
      begin
        mLines := mLines + ' ' + TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerFontsFromParent);
      end;
    end;
  end;

begin
  mLines := '';
  mCount := 0;
  for mFont in AFonts do
  begin
    Line(mFont.Component, TAtlasFontsColors.FontText(mFont.Font, TAtlasFontsDialog.StyleNames), mFont.ToParent);
  end;
  for mColor in AColors do
  begin
    Line(mColor.Component, mColor.Color, mColor.ToParent);
  end;
  Result := (mCount > 0) and (MessageDlg(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerFontsPreview,
    [mCount, mLines]), mtConfirmation, [mbOK, mbCancel], 0) = mrOk);
end;

procedure ApplyFont(ARoot: TComponent; const AChange: TAtlasFontChange; APixelsPerInch: Integer);
var
  mComponent: TComponent;
  mFont: TFont;
begin
  mComponent := Find(ARoot, AChange.Component);
  mFont := FontOfComponent(mComponent);
  if mFont = nil then
  begin
    Exit;
  end;
  if AChange.ToParent then
  begin
    SetFlag(mComponent, 'ParentFont', True);
    Exit;
  end;
  mFont.Name := AChange.Font.Name;
  mFont.Height := TAtlasFontsColors.HeightOf(AChange.Font.Size, APixelsPerInch);
  mFont.Style := TFontStyles(Byte(AChange.Font.Style));
  mFont.Color := StringToColor(AChange.Font.Color);
end;

procedure ApplyColor(ARoot: TComponent; const AChange: TAtlasColorChange);
var
  mComponent: TComponent;
begin
  mComponent := Find(ARoot, AChange.Component);
  if (mComponent = nil) or not HasColor(mComponent) then
  begin
    Exit;
  end;
  if AChange.ToParent then
  begin
    SetFlag(mComponent, 'ParentColor', True);
  end
  else
  begin
    SetOrdProp(mComponent, 'Color', StringToColor(AChange.Color));
  end;
end;

{ TAtlasIdeFontsColors }

constructor TAtlasIdeFontsColors.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
end;

procedure TAtlasIdeFontsColors.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

procedure TAtlasIdeFontsColors.Execute;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mDesigner: IDesigner;
  mUses: TArray<TAtlasFontUse>;
  mFonts: TArray<TAtlasFontRow>;
  mColors: TArray<TAtlasColorRow>;
  mAction: TAtlasFontsAction;
  mTab, mRow: Integer;
begin
  if not TAtlasIdeSettings.Current.DesignerFontsColors or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  mTab := 0;
  repeat
    mUses := Collect(mRoot);
    mFonts := TAtlasFontsColors.FontRows(mUses, mRoot.Name);
    mColors := TAtlasFontsColors.ColorRows(mUses, TAtlasIdeSettings.Current.DesignerFontsColorsIgnoreColors);
    mAction := TAtlasFontsDialog.Execute(mRoot.Name, mFonts, mColors,
      procedure(ANames: TArray<string>)
      var
        mName: string;
        mSelected: TArray<TComponent>;
      begin
        mSelected := nil;
        for mName in ANames do
        begin
          if (mRoot.FindComponent(mName) <> nil) then
          begin
            mSelected := mSelected + [mRoot.FindComponent(mName)];
          end;
        end;
        TAtlasDesignerAccess.Select(mDesigner, mRoot, mSelected);
      end, mTab, mRow);
    if (mAction = TAtlasFontsAction.ReplaceFont) and (mRow >= 0) and (mRow <= High(mFonts)) then
    begin
      ReplaceFont(mEditor, mRoot, mUses, mFonts[mRow], mFonts);
    end
    else if (mAction = TAtlasFontsAction.ReplaceColor) and (mRow >= 0) and (mRow <= High(mColors)) then
    begin
      ReplaceColor(mEditor, mRoot, mUses, mColors[mRow], mColors);
    end;
  until mAction = TAtlasFontsAction.Close;
end;

procedure TAtlasIdeFontsColors.ReplaceFont(const AEditor: IOTAFormEditor; ARoot: TComponent;
  const AUses: TArray<TAtlasFontUse>; const ARow: TAtlasFontRow; const AOthers: TArray<TAtlasFontRow>);
var
  mTargets: TArray<TAtlasFontKey>;
  mOther: TAtlasFontRow;
  mReplace: TAtlasFontReplace;
  mOnly: TArray<string>;
  mPlan: TArray<TAtlasFontChange>;
begin
  mTargets := nil;
  for mOther in AOthers do
  begin
    if not mOther.Font.Same(ARow.Font) then
    begin
      mTargets := mTargets + [mOther.Font];
    end;
  end;
  if not TAtlasFontReplaceDialog.ExecuteFont(ARow.Font, mTargets, Length(SelectedNames(AEditor, ARoot)) > 0,
    mReplace) then
  begin
    Exit;
  end;
  mOnly := nil;
  if mReplace.OnlySelected then
  begin
    mOnly := SelectedNames(AEditor, ARoot);
  end;
  mPlan := TAtlasFontsColors.FontPlan(AUses, TAtlasFontRule.Create(ARow.Font, mReplace.Font, cAllParts,
    mReplace.Parts), TAtlasIdeSettings.Current.DesignerFontsColorsRestoreParent, mOnly);
  Apply(AEditor, ARoot, mPlan, nil);
end;

procedure TAtlasIdeFontsColors.ReplaceColor(const AEditor: IOTAFormEditor; ARoot: TComponent;
  const AUses: TArray<TAtlasFontUse>; const ARow: TAtlasColorRow; const AOthers: TArray<TAtlasColorRow>);
var
  mTargets: TArray<string>;
  mOther: TAtlasColorRow;
  mReplace: TAtlasFontReplace;
  mOnly: TArray<string>;
  mRestore: Boolean;
  mRule: TAtlasFontRule;
begin
  mTargets := nil;
  for mOther in AOthers do
  begin
    if not SameText(mOther.Color, ARow.Color) then
    begin
      mTargets := mTargets + [mOther.Color];
    end;
  end;
  if not TAtlasFontReplaceDialog.ExecuteColor(ARow.Color, mTargets, Length(SelectedNames(AEditor, ARoot)) > 0,
    mReplace) then
  begin
    Exit;
  end;
  mOnly := nil;
  if mReplace.OnlySelected then
  begin
    mOnly := SelectedNames(AEditor, ARoot);
  end;
  mRestore := TAtlasIdeSettings.Current.DesignerFontsColorsRestoreParent;
  mRule := TAtlasFontRule.Create(TAtlasFontKey.Create('', 0, 0, ARow.Color), TAtlasFontKey.Create('', 0, 0,
    mReplace.Color), [TAtlasFontPart.Color], [TAtlasFontPart.Color]);
  Apply(AEditor, ARoot, TAtlasFontsColors.FontPlan(AUses, mRule, mRestore, mOnly),
    TAtlasFontsColors.ColorPlan(AUses, ARow.Color, mReplace.Color, mRestore, mOnly));
end;

procedure TAtlasIdeFontsColors.Apply(const AEditor: IOTAFormEditor; ARoot: TComponent;
  const AFonts: TArray<TAtlasFontChange>; const AColors: TArray<TAtlasColorChange>);
var
  mFont: TAtlasFontChange;
  mColor: TAtlasColorChange;
  mPixelsPerInch: Integer;
begin
  if Length(AFonts) + Length(AColors) = 0 then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerFontsNothing));
    Exit;
  end;
  if not Confirm(AFonts, AColors) then
  begin
    Exit;
  end;
  Remember(AEditor, ARoot, ChangedNames(AFonts, AColors));
  mPixelsPerInch := PixelsPerInchOf(ARoot);
  for mFont in AFonts do
  begin
    ApplyFont(ARoot, mFont, mPixelsPerInch);
  end;
  for mColor in AColors do
  begin
    ApplyColor(ARoot, mColor);
  end;
  if TAtlasDesignerAccess.DesignerOf(AEditor) <> nil then
  begin
    TAtlasDesignerAccess.DesignerOf(AEditor).Modified;
  end;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerFontsDone, [Length(FUndo)]));
end;

procedure TAtlasIdeFontsColors.Remember(const AEditor: IOTAFormEditor; ARoot: TComponent;
  const ANames: TArray<string>);
var
  mIndex: Integer;
  mComponent: TComponent;
  mFont: TFont;
  mState: TAtlasFontState;
begin
  FUndoFile := AEditor.FileName;
  FUndo := nil;
  // In der Reihenfolge des Formulars, damit Parents vor ihren Kindern zurückkommen.
  for mIndex := -1 to ARoot.ComponentCount - 1 do
  begin
    mComponent := ARoot;
    if mIndex >= 0 then
    begin
      mComponent := ARoot.Components[mIndex];
    end;
    mFont := FontOfComponent(mComponent);
    if (mFont = nil) or not MatchText(mComponent.Name, ANames) then
    begin
      Continue;
    end;
    mState := Default(TAtlasFontState);
    mState.Component := mComponent.Name;
    mState.FontName := mFont.Name;
    mState.FontHeight := mFont.Height;
    mState.FontStyle := mFont.Style;
    mState.FontColor := mFont.Color;
    mState.ParentFont := FlagOf(mComponent, 'ParentFont');
    if HasColor(mComponent) then
    begin
      mState.Color := TColor(GetOrdProp(mComponent, 'Color'));
      mState.ParentColor := FlagOf(mComponent, 'ParentColor');
    end;
    FUndo := FUndo + [mState];
  end;
end;

function TAtlasIdeFontsColors.CanUndo: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := (Length(FUndo) > 0) and TAtlasDesignerAccess.Current(mEditor, mRoot) and
    SameText(mEditor.FileName, FUndoFile);
end;

procedure TAtlasIdeFontsColors.Undo;
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mState: TAtlasFontState;
  mFont: TFont;
begin
  if not CanUndo or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  // Erst die eigenen Werte, dann die Parent-Schalter: so erben Kinder den wiederhergestellten Parent.
  for mState in FUndo do
  begin
    mComponent := Find(mRoot, mState.Component);
    mFont := FontOfComponent(mComponent);
    if mFont <> nil then
    begin
      mFont.Name := mState.FontName;
      mFont.Height := mState.FontHeight;
      mFont.Style := mState.FontStyle;
      mFont.Color := mState.FontColor;
      if HasColor(mComponent) then
      begin
        SetOrdProp(mComponent, 'Color', mState.Color);
      end;
    end;
  end;
  for mState in FUndo do
  begin
    mComponent := Find(mRoot, mState.Component);
    if FontOfComponent(mComponent) <> nil then
    begin
      SetFlag(mComponent, 'ParentFont', mState.ParentFont);
      SetFlag(mComponent, 'ParentColor', mState.ParentColor);
    end;
  end;
  FUndo := nil;
  if TAtlasDesignerAccess.DesignerOf(mEditor) <> nil then
  begin
    TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  end;
  Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerFontsUndone));
end;

end.
