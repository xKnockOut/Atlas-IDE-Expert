unit Atlas.IDE.Designer.LabelPairs;

// Label und Eingabefeld als Paar (#729) in der IDE. Paar, Grundlinie und
// Text für neue Labels rechnet TAtlasLabelPairs; die Grundlinie kommt aus der
// Schrift wie bei „Fast bündige Kanten“ (TAtlasIdeNearAlign.Baseline).
// - Untermenü „Label und Feld“ im Menü „Anordnen“:
//   „Labels an Feldern ausrichten“: Labels der Auswahl (ohne Auswahl alle)
//   rücken auf die Grundlinie bzw. die Textkante ihres Felds, FocusControl
//   wird gesetzt, wenn es leer ist; fehlt ein „&“, nennt die Meldung einen
//   freien Buchstaben. „Label erzeugen“: je markiertem Feld ohne Label ein
//   TLabel links oder darüber. „Paar lösen“/„Paar verbinden“: markierte
//   Labels folgen ihrem Feld nicht mehr bzw. wieder; gemerkt je Ordner in
//   .atlas-labelpairs.json. „Label rückgängig“: letzte Ausrichtung oder die
//   erzeugten Labels.
// - Beim Bearbeiten (IDesignNotification.ItemsModified, nach dem laufenden
//   Ereignis): Wird ein Feld verschoben, wandern seine Labels mit
//   (moveTogether); ändert sich seine Höhe, rücken sie auf die neue
//   Grundlinie. Ein abgelegtes oder verschobenes Label neben einem Feld rastet
//   ein (baseline) und bekommt FocusControl (focusControl). Mit gedrückter
//   Alt-Taste geschieht nichts.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Vcl.Controls,
  DesignIntf,
  Atlas.IDE.Designer.Snapshot;

type
{$SCOPEDENUMS ON}
  TAtlasPairsCommand = (AlignLabels, CreateLabels, Release, Join, Undo);
{$SCOPEDENUMS OFF}

  TAtlasIdeLabelPairs = class
  private type
    TNotification = class(TInterfacedObject, IDesignNotification)
    private
      FOwner: TAtlasIdeLabelPairs;
    public
      procedure ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
      procedure ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
      procedure ItemsModified(const ADesigner: IDesigner);
      procedure SelectionChanged(const ADesigner: IDesigner; const ASelection: IDesignerSelections);
      procedure DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
      procedure DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
    end;
  public const
    cFileName = '.atlas-labelpairs.json';
  private class var
    FCurrent: TAtlasIdeLabelPairs;
  private
    FOnMessage: TProc<string>;
    FSnapshot: TAtlasDesignerSnapshot;
    FCreated: TArray<string>;
    FCreatedFile: string;
    FNotification: TNotification;
    FNotificationRef: IDesignNotification;
    FRoot: TComponent;
    FBounds: TDictionary<string, TRect>;
    FBusy: Boolean;
    FQueued: Boolean;
    procedure Say(const AText: string);
    procedure Changed;
    procedure Follow;
    procedure Remember(ARoot: TComponent);
    function FollowControls(ARoot: TComponent; const AReleased: TArray<string>): Boolean;
    procedure DoAlign;
    procedure DoCreate;
    procedure DoMark(ARelease: Boolean);
    procedure DoUndo;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    procedure Execute(ACommand: TAtlasPairsCommand);
    function CanUndo: Boolean;
    /// <summary>Gibt es in der Auswahl ein Feld ohne Label?</summary>
    function CanCreate: Boolean;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  System.TypInfo,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  ToolsAPI,
  Atlas.Core.Designer.LabelPairs,
  Atlas.Core.Designer.NearAlign,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.NearAlign,
  Atlas.IDE.Foundation.Settings;

const
  cLeftGap = 8;
  cAboveGap = 3;

function IsLabel(AControl: TControl): Boolean;
begin
  Result := (AControl is TCustomLabel) or (AControl is TCustomStaticText);
end;

function IsField(AControl: TControl): Boolean;
begin
  Result := (AControl is TCustomEdit) or (AControl is TCustomComboBox) or (AControl is TCustomListBox) or
    (AControl is TCommonCalendar);
end;

function FocusOf(ALabel: TControl): TObject;
begin
  Result := nil;
  if IsPublishedProp(ALabel, 'FocusControl') and (PropType(ALabel, 'FocusControl') = tkClass) then
  begin
    Result := GetObjectProp(ALabel, 'FocusControl');
  end;
end;

function Contains(const AList: TArray<string>; const AName: string): Boolean;
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if SameText(mItem, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Felder im selben Parent wie AControl, die ARoot gehören.</summary>
function FieldsBeside(AControl: TControl; ARoot: TComponent): TArray<TControl>;
var
  mIndex: Integer;
  mOther: TControl;
begin
  Result := nil;
  if AControl.Parent = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to AControl.Parent.ControlCount - 1 do
  begin
    mOther := AControl.Parent.Controls[mIndex];
    if (mOther.Owner = ARoot) and IsField(mOther) then
    begin
      Result := Result + [mOther];
    end;
  end;
end;

/// <summary>Feld zu ALabel nach Lage; nil ohne. ASide: links oder darüber.</summary>
function PartnerOf(ALabel: TControl; ARoot: TComponent; ADistance: Integer; out ASide: TAtlasPairSide): TControl;
var
  mFields: TArray<TControl>;
  mRects: TArray<TRect>;
  mField: TControl;
  mMatch: TAtlasPairMatch;
begin
  Result := nil;
  ASide := TAtlasPairSide.None;
  mFields := FieldsBeside(ALabel, ARoot);
  mRects := nil;
  for mField in mFields do
  begin
    mRects := mRects + [mField.BoundsRect];
  end;
  mMatch := TAtlasLabelPairs.FindField(ALabel.BoundsRect, mRects, ADistance);
  if mMatch.Field >= 0 then
  begin
    Result := mFields[mMatch.Field];
    ASide := mMatch.Side;
  end;
end;

/// <summary>Label an sein Feld rücken und FocusControl setzen; True bei Änderung.</summary>
function Snap(ALabel, AField: TControl; ASide: TAtlasPairSide; const ASettings: TAtlasPluginSettings;
  ACanvas: TCanvas): Boolean;
var
  mAscent, mBaseline: Integer;
begin
  Result := False;
  if ASettings.DesignerLabelPairsFocusControl and (FocusOf(ALabel) = nil) and
    IsPublishedProp(ALabel, 'FocusControl') and (AField is TWinControl) then
  begin
    SetObjectProp(ALabel, 'FocusControl', AField);
    Result := True;
  end;
  if not ASettings.DesignerLabelPairsBaseline then
  begin
    Exit;
  end;
  if ASide = TAtlasPairSide.Above then
  begin
    Result := Result or (ALabel.Left <> AField.Left + TAtlasLabelPairs.cTextIndent);
    ALabel.Left := AField.Left + TAtlasLabelPairs.cTextIndent;
    Exit;
  end;
  mAscent := TAtlasIdeNearAlign.Baseline(ALabel, ACanvas) - ALabel.Top;
  mBaseline := TAtlasIdeNearAlign.Baseline(AField, ACanvas);
  if (mAscent >= 0) and (mBaseline >= 0) and (ALabel.Top <> TAtlasLabelPairs.BaselineTop(mBaseline, mAscent)) then
  begin
    ALabel.Top := TAtlasLabelPairs.BaselineTop(mBaseline, mAscent);
    Result := True;
  end;
end;

/// <summary>Tastenkürzel der Captions im Parent von AControl, als Großbuchstaben.</summary>
function UsedKeys(AControl: TControl): string;
var
  mIndex: Integer;
  mText: string;
begin
  Result := '';
  for mIndex := 0 to AControl.Parent.ControlCount - 1 do
  begin
    if TAtlasDesignerAccess.PropText(AControl.Parent.Controls[mIndex], 'Caption', mText) and (Pos('&', mText) > 0) then
    begin
      Result := Result + UpperCase(Copy(mText, Pos('&', mText) + 1, 1));
    end;
  end;
end;

function ReleasedPath(const AFileName: string): string;
begin
  Result := TPath.Combine(ExtractFilePath(AFileName), TAtlasIdeLabelPairs.cFileName);
end;

/// <summary>Gelöste Paare (Namen der Labels) je Formulardatei; leer ohne Datei.</summary>
function LoadReleased(const AFileName: string): TAtlasNearExceptions;
begin
  Result := TAtlasNearExceptions.Create;
  if not FileExists(ReleasedPath(AFileName)) then
  begin
    Exit;
  end;
  try
    Result.LoadJson(TFile.ReadAllText(ReleasedPath(AFileName), TEncoding.UTF8));
  except
    on EInOutError do
      Result.LoadJson('');
    on EFileStreamError do
      Result.LoadJson('');
  end;
end;

function ReleasedNames(const AFileName: string): TArray<string>;
var
  mReleased: TAtlasNearExceptions;
begin
  mReleased := LoadReleased(AFileName);
  try
    Result := mReleased.Keys(ExtractFileName(AFileName));
  finally
    mReleased.Free;
  end;
end;

{ TAtlasIdeLabelPairs.TNotification }

procedure TAtlasIdeLabelPairs.TNotification.ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
begin
end;

procedure TAtlasIdeLabelPairs.TNotification.ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
begin
end;

procedure TAtlasIdeLabelPairs.TNotification.ItemsModified(const ADesigner: IDesigner);
begin
  if FOwner <> nil then
  begin
    FOwner.Changed;
  end;
end;

procedure TAtlasIdeLabelPairs.TNotification.SelectionChanged(const ADesigner: IDesigner;
  const ASelection: IDesignerSelections);
begin
  // Vor dem ersten Ziehen den Stand des Formulars kennen.
  if (FOwner <> nil) and not FOwner.FBusy and (ADesigner <> nil) and (ADesigner.Root <> FOwner.FRoot) then
  begin
    FOwner.Remember(ADesigner.Root);
  end;
end;

procedure TAtlasIdeLabelPairs.TNotification.DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
begin
end;

procedure TAtlasIdeLabelPairs.TNotification.DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
begin
end;

{ TAtlasIdeLabelPairs }

constructor TAtlasIdeLabelPairs.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FSnapshot := TAtlasDesignerSnapshot.Create;
  FBounds := TDictionary<string, TRect>.Create;
  FNotification := TNotification.Create;
  FNotification.FOwner := Self;
  FNotificationRef := FNotification;
  RegisterDesignNotification(FNotificationRef);
  FCurrent := Self;
end;

destructor TAtlasIdeLabelPairs.Destroy;
begin
  if FCurrent = Self then
  begin
    FCurrent := nil;
  end;
  if FNotification <> nil then
  begin
    FNotification.FOwner := nil;
    UnregisterDesignNotification(FNotificationRef);
    FNotificationRef := nil;
  end;
  FBounds.Free;
  FSnapshot.Free;
  inherited Destroy;
end;

procedure TAtlasIdeLabelPairs.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

procedure TAtlasIdeLabelPairs.Remember(ARoot: TComponent);
var
  mIndex: Integer;
begin
  FRoot := ARoot;
  FBounds.Clear;
  if ARoot = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    if ARoot.Components[mIndex] is TControl then
    begin
      FBounds.AddOrSetValue(ARoot.Components[mIndex].Name, TControl(ARoot.Components[mIndex]).BoundsRect);
    end;
  end;
end;

procedure TAtlasIdeLabelPairs.Changed;
var
  mOwner: TAtlasIdeLabelPairs;
begin
  if not TAtlasIdeSettings.Current.DesignerLabelPairs then
  begin
    FRoot := nil;
    Exit;
  end;
  if FBusy or FQueued then
  begin
    Exit;
  end;
  // Erst nach dem laufenden Ereignis: Dann stehen Lage und Größe fest.
  FQueued := True;
  mOwner := Self;
  TAtlasMainThread.ForceQueue(TAtlasFeature.DesignerBar,
    procedure
    begin
      if FCurrent = mOwner then
      begin
        mOwner.FQueued := False;
        TAtlasGuard.Run(TAtlasFeature.DesignerBar,
          procedure
          begin
            mOwner.Follow;
          end);
      end;
    end);
end;

procedure TAtlasIdeLabelPairs.Follow;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Remember(nil);
    Exit;
  end;
  // Alt beim Ziehen löst das Paar für diesen Vorgang.
  if (mRoot = FRoot) and (GetKeyState(VK_MENU) >= 0) and
    FollowControls(mRoot, ReleasedNames(mEditor.FileName)) and (TAtlasDesignerAccess.DesignerOf(mEditor) <> nil) then
  begin
    FBusy := True;
    try
      TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
    finally
      FBusy := False;
    end;
  end;
  Remember(mRoot);
end;

/// <summary>Labels von AField nach dem alten Stand (FocusControl oder Lage).</summary>
function LabelsOf(AField: TControl; ARoot: TComponent; const AOld: TDictionary<string, TRect>;
  ADistance: Integer): TArray<TControl>;
var
  mIndex: Integer;
  mControl: TControl;
  mOldLabel, mOldField: TRect;
begin
  Result := nil;
  if (AField.Parent = nil) or not AOld.TryGetValue(AField.Name, mOldField) then
  begin
    Exit;
  end;
  for mIndex := 0 to AField.Parent.ControlCount - 1 do
  begin
    mControl := AField.Parent.Controls[mIndex];
    if (mControl.Owner = ARoot) and IsLabel(mControl) and AOld.TryGetValue(mControl.Name, mOldLabel) and
      ((FocusOf(mControl) = AField) or (TAtlasLabelPairs.FindField(mOldLabel, [mOldField], ADistance).Field = 0)) then
    begin
      Result := Result + [mControl];
    end;
  end;
end;

/// <summary>Vom Benutzer geänderte Steuerelemente (neu oder mit anderer Lage).</summary>
function Moved(ARoot: TComponent; const AOld: TDictionary<string, TRect>): TArray<TControl>;
var
  mIndex: Integer;
  mControl: TControl;
  mOld: TRect;
begin
  Result := nil;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    if not (ARoot.Components[mIndex] is TControl) then
    begin
      Continue;
    end;
    mControl := TControl(ARoot.Components[mIndex]);
    if (mControl.Parent <> nil) and (not AOld.TryGetValue(mControl.Name, mOld) or (mOld <> mControl.BoundsRect)) then
    begin
      Result := Result + [mControl];
    end;
  end;
end;

/// <summary>Labels eines verschobenen Felds mitnehmen; True bei Änderung.</summary>
function FollowField(AField: TControl; ARoot: TComponent; const AOld: TDictionary<string, TRect>;
  const AMoved: TArray<TControl>; const AReleased: TArray<string>; ACanvas: TCanvas): Boolean;
var
  mSettings: TAtlasPluginSettings;
  mOld: TRect;
  mLabel, mOther: TControl;
  mSide: TAtlasPairSide;
  mTogether: Boolean;
begin
  Result := False;
  mSettings := TAtlasIdeSettings.Current;
  if not AOld.TryGetValue(AField.Name, mOld) then
  begin
    Exit;
  end;
  for mLabel in LabelsOf(AField, ARoot, AOld, mSettings.DesignerLabelPairsPairDistance) do
  begin
    mTogether := False;
    for mOther in AMoved do
    begin
      mTogether := mTogether or (mOther = mLabel);
    end;
    if mTogether or Contains(AReleased, mLabel.Name) or not mSettings.DesignerLabelPairsMoveTogether then
    begin
      Continue;
    end;
    mLabel.SetBounds(mLabel.Left + AField.Left - mOld.Left, mLabel.Top + AField.Top - mOld.Top, mLabel.Width,
      mLabel.Height);
    Result := True;
    if (AField.Height <> mOld.Height) and (PartnerOf(mLabel, ARoot, mSettings.DesignerLabelPairsPairDistance,
      mSide) = AField) then
    begin
      Snap(mLabel, AField, mSide, mSettings, ACanvas);
    end;
  end;
end;

/// <summary>Abgelegtes oder verschobenes Label an seinem Feld einrasten; True bei Änderung.</summary>
function FollowLabel(ALabel: TControl; ARoot: TComponent; const AReleased: TArray<string>; ACanvas: TCanvas): Boolean;
var
  mSettings: TAtlasPluginSettings;
  mField: TControl;
  mSide: TAtlasPairSide;
begin
  Result := False;
  mSettings := TAtlasIdeSettings.Current;
  if Contains(AReleased, ALabel.Name) then
  begin
    Exit;
  end;
  mField := PartnerOf(ALabel, ARoot, mSettings.DesignerLabelPairsPairDistance, mSide);
  if mField <> nil then
  begin
    Result := Snap(ALabel, mField, mSide, mSettings, ACanvas);
  end;
end;

function TAtlasIdeLabelPairs.FollowControls(ARoot: TComponent; const AReleased: TArray<string>): Boolean;
var
  mMoved: TArray<TControl>;
  mControl: TControl;
  mBitmap: TBitmap;
begin
  Result := False;
  mMoved := Moved(ARoot, FBounds);
  if Length(mMoved) = 0 then
  begin
    Exit;
  end;
  mBitmap := TBitmap.Create;
  try
    for mControl in mMoved do
    begin
      if IsField(mControl) then
      begin
        Result := FollowField(mControl, ARoot, FBounds, mMoved, AReleased, mBitmap.Canvas) or Result;
      end
      else if IsLabel(mControl) then
      begin
        Result := FollowLabel(mControl, ARoot, AReleased, mBitmap.Canvas) or Result;
      end;
    end;
  finally
    mBitmap.Free;
  end;
end;

/// <summary>Labels der Auswahl oder der markierten Felder; ohne Auswahl alle des Formulars.</summary>
function TargetLabels(ARoot: TComponent; const ASelected: TArray<TComponent>): TArray<TControl>;
var
  mIndex: Integer;
  mControl: TControl;
  mItem: TComponent;
  mTaken: Boolean;
begin
  Result := nil;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    if not (ARoot.Components[mIndex] is TControl) or not IsLabel(TControl(ARoot.Components[mIndex])) then
    begin
      Continue;
    end;
    mControl := TControl(ARoot.Components[mIndex]);
    mTaken := Length(ASelected) = 0;
    for mItem in ASelected do
    begin
      mTaken := mTaken or (mItem = mControl) or (mItem = FocusOf(mControl));
    end;
    if mTaken and (mControl.Parent <> nil) then
    begin
      Result := Result + [mControl];
    end;
  end;
end;

procedure TAtlasIdeLabelPairs.DoAlign;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSettings: TAtlasPluginSettings;
  mLabel, mField: TControl;
  mSide: TAtlasPairSide;
  mBitmap: TBitmap;
  mCount: Integer;
  mText, mSuggestion: string;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) or (TAtlasDesignerAccess.DesignerOf(mEditor) = nil) then
  begin
    Exit;
  end;
  mSettings := TAtlasIdeSettings.Current;
  FSnapshot.Take(mEditor.FileName, mRoot);
  FCreated := nil;
  mCount := 0;
  mBitmap := TBitmap.Create;
  FBusy := True;
  try
    for mLabel in TargetLabels(mRoot, TAtlasDesignerAccess.Selection(mEditor, mRoot)) do
    begin
      mField := PartnerOf(mLabel, mRoot, mSettings.DesignerLabelPairsPairDistance, mSide);
      if (mField <> nil) and Snap(mLabel, mField, mSide, mSettings, mBitmap.Canvas) then
      begin
        Inc(mCount);
      end;
      if (mField <> nil) and TAtlasDesignerAccess.PropText(mLabel, 'Caption', mText) then
      begin
        mSuggestion := TAtlasLabelPairs.FreeAccelerator(mText, UsedKeys(mLabel));
        if mSuggestion <> '' then
        begin
          Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerPairsAccelerator, [mLabel.Name, mSuggestion]));
        end;
      end;
    end;
    TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  finally
    FBusy := False;
    mBitmap.Free;
  end;
  Remember(mRoot);
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerPairsAligned, [mCount]));
end;

/// <summary>Markierte Felder ohne Label (weder FocusControl noch Lage).</summary>
function Unlabeled(ARoot: TComponent; const ASelected: TArray<TComponent>; ADistance: Integer): TArray<TControl>;
var
  mItem: TComponent;
  mIndex: Integer;
  mSide: TAtlasPairSide;
  mHas: Boolean;
  mControl: TControl;
begin
  Result := nil;
  for mItem in ASelected do
  begin
    if not (mItem is TControl) or not IsField(TControl(mItem)) or (TControl(mItem).Parent = nil) then
    begin
      Continue;
    end;
    mHas := False;
    for mIndex := 0 to ARoot.ComponentCount - 1 do
    begin
      if (ARoot.Components[mIndex] is TControl) and IsLabel(TControl(ARoot.Components[mIndex])) then
      begin
        mControl := TControl(ARoot.Components[mIndex]);
        mHas := mHas or (FocusOf(mControl) = mItem) or ((mControl.Parent = TControl(mItem).Parent) and
          (PartnerOf(mControl, ARoot, ADistance, mSide) = mItem));
      end;
    end;
    if not mHas then
    begin
      Result := Result + [TControl(mItem)];
    end;
  end;
end;

function UniqueName(ARoot: TComponent; const AName: string): string;
var
  mNumber: Integer;
begin
  Result := AName;
  mNumber := 1;
  while ARoot.FindComponent(Result) <> nil do
  begin
    Inc(mNumber);
    Result := AName + IntToStr(mNumber);
  end;
end;

/// <summary>Neues Label für AField anlegen, beschriften und an seinen Platz rücken.</summary>
function NewLabel(const ADesigner: IDesigner; ARoot: TComponent; AField: TControl;
  const ASettings: TAtlasPluginSettings; ACanvas: TCanvas): TControl;
var
  mSide: TAtlasPairSide;
  mPoint: TPoint;
  mAscent, mGap: Integer;
begin
  Result := TControl(ADesigner.CreateComponent(TLabel, AField.Parent, AField.Left, AField.Top, 0, 0));
  Result.Name := UniqueName(ARoot, TAtlasLabelPairs.NameFor(AField.Name));
  TLabel(Result).Caption := TAtlasLabelPairs.CaptionFor(AField.Name, ASettings.DesignerLabelPairsAbbreviations);
  if AField is TWinControl then
  begin
    TLabel(Result).FocusControl := TWinControl(AField);
  end;
  mSide := TAtlasPairSide.Left;
  if SameText(ASettings.DesignerLabelPairsNewLabelPosition, TAtlasPluginSettings.cLabelAbove) then
  begin
    mSide := TAtlasPairSide.Above;
  end;
  mAscent := TAtlasIdeNearAlign.Baseline(Result, ACanvas) - Result.Top;
  mGap := cLeftGap;
  if mSide = TAtlasPairSide.Above then
  begin
    mGap := cAboveGap;
  end;
  mPoint := TAtlasLabelPairs.Place(AField.BoundsRect, TSize.Create(Result.Width, Result.Height), mSide, mGap,
    TAtlasIdeNearAlign.Baseline(AField, ACanvas), mAscent);
  Result.SetBounds(mPoint.X, mPoint.Y, Result.Width, Result.Height);
end;

procedure TAtlasIdeLabelPairs.DoCreate;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSettings: TAtlasPluginSettings;
  mField: TControl;
  mBitmap: TBitmap;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) or (TAtlasDesignerAccess.DesignerOf(mEditor) = nil) then
  begin
    Exit;
  end;
  mSettings := TAtlasIdeSettings.Current;
  FSnapshot.Take(mEditor.FileName, mRoot);
  FCreated := nil;
  FCreatedFile := mEditor.FileName;
  mBitmap := TBitmap.Create;
  FBusy := True;
  try
    for mField in Unlabeled(mRoot, TAtlasDesignerAccess.Selection(mEditor, mRoot),
      mSettings.DesignerLabelPairsPairDistance) do
    begin
      FCreated := FCreated + [NewLabel(TAtlasDesignerAccess.DesignerOf(mEditor), mRoot, mField, mSettings,
        mBitmap.Canvas).Name];
    end;
    TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  finally
    FBusy := False;
    mBitmap.Free;
  end;
  Remember(mRoot);
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerPairsCreated, [Length(FCreated)]));
end;

procedure TAtlasIdeLabelPairs.DoMark(ARelease: Boolean);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mReleased: TAtlasNearExceptions;
  mNames: TArray<string>;
  mLabel: TControl;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) or
    (Length(TAtlasDesignerAccess.Selection(mEditor, mRoot)) = 0) then
  begin
    Exit;
  end;
  mNames := nil;
  for mLabel in TargetLabels(mRoot, TAtlasDesignerAccess.Selection(mEditor, mRoot)) do
  begin
    mNames := mNames + [mLabel.Name];
  end;
  mReleased := LoadReleased(mEditor.FileName);
  try
    if ARelease then
    begin
      mReleased.Add(ExtractFileName(mEditor.FileName), mNames);
    end
    else
    begin
      mReleased.RemoveNames(ExtractFileName(mEditor.FileName), mNames);
    end;
    try
      if mReleased.Changed then
      begin
        TFile.WriteAllText(ReleasedPath(mEditor.FileName), mReleased.ToJson, TEncoding.UTF8);
      end;
      Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerPairsMarked, [Length(mNames)]));
    except
      on mError: EInOutError do
        Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerPairsSaveFailed, [mError.Message]));
      on mError: EFileStreamError do
        Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerPairsSaveFailed, [mError.Message]));
    end;
  finally
    mReleased.Free;
  end;
end;

function TAtlasIdeLabelPairs.CanUndo: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := FSnapshot.CanRestore or ((Length(FCreated) > 0) and TAtlasDesignerAccess.Current(mEditor, mRoot) and
    SameText(mEditor.FileName, FCreatedFile));
end;

function TAtlasIdeLabelPairs.CanCreate: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := TAtlasDesignerAccess.Current(mEditor, mRoot) and (Length(Unlabeled(mRoot,
    TAtlasDesignerAccess.Selection(mEditor, mRoot), TAtlasIdeSettings.Current.DesignerLabelPairsPairDistance)) > 0);
end;

procedure TAtlasIdeLabelPairs.DoUndo;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mComponent: IOTAComponent;
  mName: string;
begin
  if not CanUndo or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  FBusy := True;
  try
    // Erst die erzeugten Labels löschen, dann die Lage der übrigen zurücksetzen.
    if SameText(mEditor.FileName, FCreatedFile) then
    begin
      for mName in FCreated do
      begin
        mComponent := mEditor.FindComponent(mName);
        if mComponent <> nil then
        begin
          mComponent.Delete;
        end;
      end;
    end;
    FCreated := nil;
    FSnapshot.Restore;
  finally
    FBusy := False;
  end;
  Remember(mRoot);
  Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerPairsUndone));
end;

procedure TAtlasIdeLabelPairs.Execute(ACommand: TAtlasPairsCommand);
begin
  if not TAtlasIdeSettings.Current.DesignerLabelPairs then
  begin
    Exit;
  end;
  case ACommand of
    TAtlasPairsCommand.AlignLabels:
      DoAlign;
    TAtlasPairsCommand.CreateLabels:
      DoCreate;
    TAtlasPairsCommand.Release:
      DoMark(True);
    TAtlasPairsCommand.Join:
      DoMark(False);
    TAtlasPairsCommand.Undo:
      DoUndo;
  end;
end;

end.
