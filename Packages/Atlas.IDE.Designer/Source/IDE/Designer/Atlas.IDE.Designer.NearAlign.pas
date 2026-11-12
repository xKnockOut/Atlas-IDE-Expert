unit Atlas.IDE.Designer.NearAlign;

// Untermenü „Fast bündige Kanten“ (#746) im Menü „Anordnen“ in der IDE. Die
// Rechnung macht TAtlasNearAlign je Parent mit seinen Kindern:
// - Übergangen werden Steuerelemente mit Align und Klassen aus
//   designer.nearAlignment.ignoreClasses (samt Nachfahren).
// - Die Grundlinie ist aus der Schrift genähert: Beschriftung oben plus
//   Oberlänge, Eingabefelder, Listen und Knöpfe mittig.
// - „Anzeigen“ rahmt die betroffenen Steuerelemente einige Sekunden mit
//   Kante und Versatz ein (TAtlasDesignerOutlines) und schreibt die Funde in
//   die Meldungsansicht.
// - „Alle angleichen“ setzt alle Funde um; „Angleichen rückgängig“ setzt den
//   Stand davor zurück (TAtlasDesignerSnapshot).
// - Ausnahmen liegen je Ordner in .atlas-nearalign.json neben den Formularen
//   (TAtlasNearExceptions), damit sie mit dem Projekt eingecheckt werden.
// Nur im Hauptthread.

interface

uses
  Winapi.Windows, // vor Vcl.Graphics, sonst verdeckt es TBitmap
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  Atlas.UI.Designer.Outlines,
  Atlas.IDE.Designer.Snapshot;

type
{$SCOPEDENUMS ON}
  TAtlasNearCommand = (Show, FixAll, MarkSelection, RemoveSelection, Undo);
{$SCOPEDENUMS OFF}

  TAtlasIdeNearAlign = class
  public const
    cFileName = '.atlas-nearalign.json';
    cShowMilliseconds = 8000;
  private
    FOnMessage: TProc<string>;
    FSnapshot: TAtlasDesignerSnapshot;
    FOutlines: TAtlasDesignerOutlines;
    FTimer: TTimer;
    procedure Say(const AText: string);
    procedure TimerTick(Sender: TObject);
    procedure ShowOutlines(ARoot: TWinControl; const AOutlines: TArray<TAtlasOutline>);
    procedure HideOutlines;
    procedure DoShow;
    procedure DoFixAll;
    procedure DoMark(AAdd: Boolean);
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    procedure Execute(ACommand: TAtlasNearCommand);
    function CanUndo: Boolean;
    procedure ApplyTheme;
    /// <summary>Grundlinie von AControl im Parent aus der Schrift genähert; -1 ohne einzeiligen Text.</summary>
    class function Baseline(AControl: TControl; ACanvas: TCanvas): Integer; static;
  end;

implementation

uses
  System.Types,
  System.IOUtils,
  Vcl.StdCtrls,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Designer.NearAlign,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings;

const
  cListLimit = 10;

type
  /// <summary>Zugang zu Font (geschützt in TControl).</summary>
  TControlAccess = class(TControl);

  /// <summary>Ein Parent: seine Kinder, deren Daten für die Rechnung und die Funde.</summary>
  TNearGroup = record
    Controls: TArray<TControl>;
    Items: TArray<TAtlasAlignItem>;
    Findings: TArray<TAtlasNearFinding>;
  end;

  /// <summary>Formular und Einstellungen eines Laufs.</summary>
  TNearScan = record
    Root: TWinControl;
    FormFile: string;
    Groups: TArray<TNearGroup>;
  end;

function Ignored(AControl: TControl; const AClasses: TArray<string>): Boolean;
var
  mClass: TClass;
  mName: string;
begin
  Result := AControl.Align <> alNone;
  mClass := AControl.ClassType;
  while not Result and (mClass <> nil) do
  begin
    for mName in AClasses do
    begin
      Result := Result or SameText(Trim(mName), mClass.ClassName);
    end;
    mClass := mClass.ClassParent;
  end;
end;

/// <summary>Hat AControl eine einzeilige Textzeile (Beschriftung, Eingabefeld, Liste, Knopf)?</summary>
function HasTextLine(AControl: TControl): Boolean;
begin
  Result := (AControl is TCustomLabel) or (AControl is TCustomEdit) or (AControl is TCustomComboBox) or
    (AControl is TButtonControl) or (AControl is TCustomStaticText);
  Result := Result and not (AControl is TCustomMemo);
end;

/// <summary>Grundlinie aus der Schrift genähert; -1 ohne einzeiligen Text.</summary>
function BaselineOf(AControl: TControl; ACanvas: TCanvas): Integer;
var
  mMetric: TTextMetric;
begin
  Result := -1;
  if not HasTextLine(AControl) then
  begin
    Exit;
  end;
  ACanvas.Font := TControlAccess(AControl).Font;
  if not GetTextMetrics(ACanvas.Handle, mMetric) then
  begin
    Exit;
  end;
  if AControl is TCustomLabel then
  begin
    Result := AControl.Top + mMetric.tmAscent;
  end
  else
  begin
    Result := AControl.Top + (AControl.Height - mMetric.tmHeight) div 2 + mMetric.tmAscent;
  end;
end;

function GroupOf(AParent: TWinControl; ARoot: TComponent; const AClasses: TArray<string>;
  ACanvas: TCanvas): TNearGroup;
var
  mIndex: Integer;
  mControl: TControl;
begin
  Result.Controls := nil;
  Result.Items := nil;
  Result.Findings := nil;
  for mIndex := 0 to AParent.ControlCount - 1 do
  begin
    mControl := AParent.Controls[mIndex];
    if mControl.Owner <> ARoot then
    begin
      Continue;
    end;
    Result.Controls := Result.Controls + [mControl];
    Result.Items := Result.Items + [TAtlasAlignItem.Create(mControl.Name, mControl.BoundsRect,
      BaselineOf(mControl, ACanvas), Ignored(mControl, AClasses))];
  end;
end;

function ExceptionsPath(const AFileName: string): string;
begin
  Result := TPath.Combine(ExtractFilePath(AFileName), TAtlasIdeNearAlign.cFileName);
end;

/// <summary>Ausnahmen aus der Datei neben AFileName; leer ohne Datei oder bei unbrauchbarem Inhalt.</summary>
function LoadExceptions(const AFileName: string): TAtlasNearExceptions;
begin
  Result := TAtlasNearExceptions.Create;
  if not FileExists(ExceptionsPath(AFileName)) then
  begin
    Exit;
  end;
  try
    Result.LoadJson(TFile.ReadAllText(ExceptionsPath(AFileName), TEncoding.UTF8));
  except
    on EInOutError do
      Result.LoadJson('');
    on EFileStreamError do
      Result.LoadJson('');
  end;
end;

/// <summary>Alle Parents des aktiven Formulars mit ihren Funden; False ohne Formular mit Fenster.</summary>
function Scan(out AScan: TNearScan): Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSettings: TAtlasPluginSettings;
  mExceptions: TAtlasNearExceptions;
  mBitmap: TBitmap;
  mParents: TArray<TWinControl>;
  mParent: TWinControl;
  mGroup: TNearGroup;
  mIndex: Integer;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.DesignerNearAlignment and TAtlasDesignerAccess.Current(mEditor, mRoot) and
    (mRoot is TWinControl);
  if not Result then
  begin
    Exit;
  end;
  AScan.Root := TWinControl(mRoot);
  AScan.FormFile := mEditor.FileName;
  AScan.Groups := nil;
  mParents := [AScan.Root];
  for mIndex := 0 to mRoot.ComponentCount - 1 do
  begin
    if mRoot.Components[mIndex] is TWinControl then
    begin
      mParents := mParents + [TWinControl(mRoot.Components[mIndex])];
    end;
  end;
  mExceptions := LoadExceptions(AScan.FormFile);
  mBitmap := TBitmap.Create;
  try
    for mParent in mParents do
    begin
      mGroup := GroupOf(mParent, mRoot, mSettings.DesignerNearAlignmentIgnoreClasses.Split([',', ';']),
        mBitmap.Canvas);
      mGroup.Findings := TAtlasNearAlign.Find(mGroup.Items, mSettings.DesignerNearAlignmentTolerance,
        mSettings.DesignerNearAlignmentBaseline, mExceptions.Keys(ExtractFileName(AScan.FormFile)));
      if Length(mGroup.Findings) > 0 then
      begin
        AScan.Groups := AScan.Groups + [mGroup];
      end;
    end;
  finally
    mBitmap.Free;
    mExceptions.Free;
  end;
end;

function FindingCount(const AScan: TNearScan): Integer;
var
  mGroup: TNearGroup;
begin
  Result := 0;
  for mGroup in AScan.Groups do
  begin
    Inc(Result, Length(mGroup.Findings));
  end;
end;

/// <summary>Versatz mit Vorzeichen (Format kennt kein „+“).</summary>
function Signed(AValue: Integer): string;
begin
  Result := IntToStr(AValue);
  if AValue > 0 then
  begin
    Result := '+' + Result;
  end;
end;

function FindingText(const AGroup: TNearGroup; const AFinding: TAtlasNearFinding): string;
begin
  Result := TAtlasNearAlign.KeyOf(AGroup.Items[AFinding.Item].Name, AFinding.Edge) + ' ' + Signed(AFinding.Offset);
end;

/// <summary>Ein Rahmen je betroffenem Steuerelement, beschriftet mit Kanten und Versatz.</summary>
function OutlinesOf(const AScan: TNearScan): TArray<TAtlasOutline>;
var
  mGroup: TNearGroup;
  mIndex: Integer;
  mFinding: TAtlasNearFinding;
  mText: string;
begin
  Result := nil;
  for mGroup in AScan.Groups do
  begin
    for mIndex := 0 to High(mGroup.Controls) do
    begin
      mText := '';
      for mFinding in mGroup.Findings do
      begin
        if mFinding.Item = mIndex then
        begin
          mText := mText + ' ' + TAtlasNearAlign.EdgeName(mFinding.Edge) + ' ' + Signed(mFinding.Offset);
        end;
      end;
      if mText <> '' then
      begin
        Result := Result + [TAtlasOutline.Create(TAtlasDesignerAccess.BoundsInRoot(mGroup.Controls[mIndex],
          AScan.Root), mGroup.Controls[mIndex].Name + ':' + mText, True)];
      end;
    end;
  end;
end;

function Selected(const AScan: TNearScan): TArray<string>;
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
begin
  Result := nil;
  if TAtlasDesignerAccess.Current(mEditor, mRoot) and (mRoot = AScan.Root) then
  begin
    for mComponent in TAtlasDesignerAccess.Selection(mEditor, mRoot) do
    begin
      Result := Result + [mComponent.Name];
    end;
  end;
end;

{ TAtlasIdeNearAlign }

constructor TAtlasIdeNearAlign.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FSnapshot := TAtlasDesignerSnapshot.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cShowMilliseconds;
  FTimer.OnTimer := TimerTick;
end;

destructor TAtlasIdeNearAlign.Destroy;
begin
  FTimer.Free;
  FOutlines.Free;
  FSnapshot.Free;
  inherited Destroy;
end;

procedure TAtlasIdeNearAlign.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

procedure TAtlasIdeNearAlign.TimerTick(Sender: TObject);
begin
  HideOutlines;
end;

procedure TAtlasIdeNearAlign.ShowOutlines(ARoot: TWinControl; const AOutlines: TArray<TAtlasOutline>);
var
  mArea: TRect;
begin
  if FOutlines = nil then
  begin
    FOutlines := TAtlasDesignerOutlines.CreateOutlines(nil, Application.MainFormHandle, TAtlasIdeStyle.Colors);
  end;
  mArea := ARoot.ClientRect;
  mArea.Offset(ARoot.ClientOrigin);
  FOutlines.ShowOutlines(mArea, AOutlines);
  FTimer.Enabled := False;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeNearAlign.HideOutlines;
begin
  FTimer.Enabled := False;
  if FOutlines <> nil then
  begin
    FOutlines.HideOutlines;
  end;
end;

procedure TAtlasIdeNearAlign.ApplyTheme;
begin
  if FOutlines <> nil then
  begin
    FOutlines.ApplyColors(TAtlasIdeStyle.Colors);
  end;
end;

procedure TAtlasIdeNearAlign.DoShow;
var
  mScan: TNearScan;
  mGroup: TNearGroup;
  mFinding: TAtlasNearFinding;
  mList: TArray<string>;
begin
  if not Scan(mScan) then
  begin
    Exit;
  end;
  if FindingCount(mScan) = 0 then
  begin
    HideOutlines;
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerNearNone));
    Exit;
  end;
  mList := nil;
  for mGroup in mScan.Groups do
  begin
    for mFinding in mGroup.Findings do
    begin
      if Length(mList) < cListLimit then
      begin
        mList := mList + [FindingText(mGroup, mFinding)];
      end;
    end;
  end;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerNearFound, [FindingCount(mScan),
    string.Join(', ', mList)]));
  ShowOutlines(mScan.Root, OutlinesOf(mScan));
end;

procedure TAtlasIdeNearAlign.DoFixAll;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mScan: TNearScan;
  mGroup: TNearGroup;
  mRects: TArray<TRect>;
  mIndex: Integer;
begin
  HideOutlines;
  if not Scan(mScan) or not TAtlasDesignerAccess.Current(mEditor, mRoot) or
    (TAtlasDesignerAccess.DesignerOf(mEditor) = nil) then
  begin
    Exit;
  end;
  if FindingCount(mScan) = 0 then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerNearNone));
    Exit;
  end;
  FSnapshot.Take(mEditor.FileName, mRoot);
  for mGroup in mScan.Groups do
  begin
    mRects := TAtlasNearAlign.FixAll(mGroup.Items, mGroup.Findings);
    for mIndex := 0 to High(mGroup.Controls) do
    begin
      if mGroup.Controls[mIndex].BoundsRect <> mRects[mIndex] then
      begin
        mGroup.Controls[mIndex].BoundsRect := mRects[mIndex];
      end;
    end;
  end;
  TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerNearFixed, [FindingCount(mScan)]));
end;

/// <summary>Schlüssel aller Funde der Steuerelemente ANames.</summary>
function KeysOf(const AScan: TNearScan; const ANames: TArray<string>): TArray<string>;
var
  mGroup: TNearGroup;
  mFinding: TAtlasNearFinding;
  mName: string;
begin
  Result := nil;
  for mGroup in AScan.Groups do
  begin
    for mFinding in mGroup.Findings do
    begin
      for mName in ANames do
      begin
        if SameText(mName, mGroup.Items[mFinding.Item].Name) then
        begin
          Result := Result + [TAtlasNearAlign.KeyOf(mName, mFinding.Edge)];
        end;
      end;
    end;
  end;
end;

procedure TAtlasIdeNearAlign.DoMark(AAdd: Boolean);
var
  mScan: TNearScan;
  mExceptions: TAtlasNearExceptions;
  mForm: string;
  mCount: Integer;
begin
  HideOutlines;
  if not Scan(mScan) then
  begin
    Exit;
  end;
  mForm := ExtractFileName(mScan.FormFile);
  mExceptions := LoadExceptions(mScan.FormFile);
  try
    try
      if AAdd then
      begin
        mCount := Length(KeysOf(mScan, Selected(mScan)));
        mExceptions.Add(mForm, KeysOf(mScan, Selected(mScan)));
      end
      else
      begin
        mCount := mExceptions.RemoveNames(mForm, Selected(mScan));
      end;
      if mExceptions.Changed then
      begin
        TFile.WriteAllText(ExceptionsPath(mScan.FormFile), mExceptions.ToJson, TEncoding.UTF8);
      end;
      if AAdd then
      begin
        Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerNearExcepted, [mCount]));
      end
      else
      begin
        Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerNearRemoved, [mCount]));
      end;
    except
      on mError: EInOutError do
        Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerNearSaveFailed, [mError.Message]));
      on mError: EFileStreamError do
        Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerNearSaveFailed, [mError.Message]));
    end;
  finally
    mExceptions.Free;
  end;
end;

class function TAtlasIdeNearAlign.Baseline(AControl: TControl; ACanvas: TCanvas): Integer;
begin
  Result := BaselineOf(AControl, ACanvas);
end;

procedure TAtlasIdeNearAlign.Execute(ACommand: TAtlasNearCommand);
begin
  case ACommand of
    TAtlasNearCommand.Show:
      DoShow;
    TAtlasNearCommand.FixAll:
      DoFixAll;
    TAtlasNearCommand.MarkSelection:
      DoMark(True);
    TAtlasNearCommand.RemoveSelection:
      DoMark(False);
    TAtlasNearCommand.Undo:
      begin
        HideOutlines;
        if FSnapshot.Restore then
        begin
          Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerNearUndone));
        end;
      end;
  end;
end;

function TAtlasIdeNearAlign.CanUndo: Boolean;
begin
  Result := FSnapshot.CanRestore;
end;

end.
