unit Atlas.IDE.Debug.BreakpointSets;

// Haltepunkt-Sätze (#586) im Debugger der IDE:
// - Befehle „Haltepunkte als Satz speichern …“, „Haltepunkt-Satz wechseln …“,
//   „… hinzufügen …“ und „… löschen …“ (Menü Atlas, Befehlspalette) für das
//   aktive Projekt; Sätze liegen in <Projektordner>/.atlas/breakpoints.
// - Speichern nimmt alle Quelltext-Haltepunkte (an und aus) mit Anker an der
//   Methode und ihren Eigenschaften; Texte offener Dateien aus dem Editor.
// - Wechseln legt fehlende Haltepunkte des Satzes an, schaltet seine ein bzw.
//   aus wie gespeichert und die Haltepunkte anderer Sätze aus (gelöscht wird
//   nichts); Hinzufügen tut dasselbe ohne Ausschalten. Haltepunkte ohne Satz
//   bleiben unberührt. Nicht mehr auffindbare meldet eine Zeile je
//   Haltepunkt in den Meldungen.
// - debug.breakpointSetPerBranch: Ein Zeitgeber (10 s) fragt im Hintergrund,
//   ob die Arbeitskopie des aktiven Projekts den Branch gewechselt hat
//   (TAtlasVcsWatch, git bzw. svn nur nach geänderten Verwaltungsdateien);
//   gibt es einen Satz mit diesem Branch, wird er aktiv.
// Ein Teil der Feature-Tabelle (Teil der Befehle des Debuggers); Release hält
// den Zeitgeber an. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Debug.BreakpointSets,
  Atlas.UI.Debug.BreakpointSets;

type
  TAtlasIdeBreakpointSets = class
  private const
    cPlacesMs = 3000;
  private class var
    FMessage: TProc<string>;
    FStarted: Boolean;
    FTimer: TObject;
    /// <summary>Hält FWatchHolder (TWatchHolder) am Leben, auch für einen laufenden Auftrag.</summary>
    FWatch: IInterface;
    FWatchHolder: TObject;
    FWatchFolder: string;
    FBusy: Boolean;
    FActiveName: string;
    FBranch: string;
    // Stellen der Sätze für SetNamesAt: Schlüssel Datei|Zeile, Wert die Namen mit Zeilenumbruch getrennt.
    FPlaces: TStringList;
    FPlacesAt: UInt64;
    class procedure ReadPlaces; static;
    class procedure Report(const AText: string); static;
    class function ProjectFolder(out AFolder: string): Boolean; static;
    class function LoadSets(const AFolder: string): TAtlasBreakpointSetList; static;
    class function Capture(out AEntries: TAtlasBreakpointSetEntries): Boolean; static;
    class procedure Apply(const ASets: TAtlasBreakpointSetList; AIndex: Integer; AExclusive: Boolean;
      const APrefix: string); static;
    /// <summary>Name und Branch im Dialog erfragen; False bei Abbrechen oder unbrauchbarem Namen.</summary>
    class function AskSet(const AFolder: string; var ASet: TAtlasBreakpointSet): Boolean; static;
    /// <summary>Satz in seine Datei schreiben; False mit Meldung.</summary>
    class function WriteSet(const AFolder: string; const ASet: TAtlasBreakpointSet): Boolean; static;
    class function Choose(AMode: TAtlasBreakpointSetMode; out AFolder: string; out ASets: TAtlasBreakpointSetList;
      out AIndex: Integer): Boolean; static;
    class procedure Tick(Sender: TObject);
    class procedure BranchArrived(const ABranch: string; ASwitched: Boolean); static;
  public
    /// <summary>Teil starten: Zeitgeber für den Branch-Wechsel. AMessage schreibt eine Zeile in die
    /// Meldungsansicht.</summary>
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    class procedure SaveSet; static;
    class procedure SwitchSet; static;
    class procedure AddSet; static;
    class procedure DeleteSet; static;
    /// <summary>Namen der Sätze des aktiven Projekts, in denen ein Haltepunkt an AFileName/ALine (ab 0) steht
    /// (für das Haltepunktfenster #863). Die Sätze werden höchstens alle cPlacesMs neu gelesen.</summary>
    class function SetNamesAt(const AFileName: string; ALine: Integer): TArray<string>; static;
  end;

implementation

uses
  System.IOUtils,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Files.DataFile,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Switches,
  Atlas.IDE.Contracts.VersionControl,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Breakpoints,
  Atlas.UI.Debug.Strings;

const
  cTickMs = 10000;

type
  /// <summary>Hält die Branch-Beobachtung, solange ein Auftrag im Hintergrund läuft (auch nach Release).</summary>
  TWatchHolder = class(TInterfacedObject)
  private
    FWatch: TAtlasVcsWatch;
    FFolder: string;
  public
    constructor Create(const AFolder: string);
    destructor Destroy; override;
    property Watch: TAtlasVcsWatch read FWatch;
    property Folder: string read FFolder;
  end;

constructor TWatchHolder.Create(const AFolder: string);
begin
  inherited Create;
  FFolder := AFolder;
  FWatch := TAtlasVcsWatch.Create(TAtlasIdeVcs.ForFolder(AFolder));
end;

destructor TWatchHolder.Destroy;
begin
  FWatch.Free;
  inherited;
end;

{ Haltepunkte der IDE }

function PropsOf(const ABreakpoint: IOTABreakpoint): TAtlasBreakpointProps;
begin
  Result := TAtlasBreakpointProps.Default;
  Result.Enabled := ABreakpoint.Enabled;
  Result.Condition := ABreakpoint.Expression;
  Result.PassCount := ABreakpoint.PassCount;
  Result.Group := ABreakpoint.GroupName;
  Result.DoBreak := ABreakpoint.DoBreak;
  Result.LogMessage := ABreakpoint.LogMessage;
  Result.EvalExpression := ABreakpoint.EvalExpression;
  Result.LogResult := ABreakpoint.LogResult;
  Result.EnableGroup := ABreakpoint.EnableGroup;
  Result.DisableGroup := ABreakpoint.DisableGroup;
  Result.HandleExceptions := ABreakpoint.DoHandleExceptions;
  Result.IgnoreExceptions := ABreakpoint.DoIgnoreExceptions;
  Result.StackFrames := ABreakpoint.StackFramesToLog;
end;

procedure ApplyProps(const ABreakpoint: IOTABreakpoint; const AProps: TAtlasBreakpointProps);
begin
  ABreakpoint.Expression := AProps.Condition;
  ABreakpoint.PassCount := AProps.PassCount;
  ABreakpoint.GroupName := AProps.Group;
  ABreakpoint.DoBreak := AProps.DoBreak;
  ABreakpoint.LogMessage := AProps.LogMessage;
  ABreakpoint.EvalExpression := AProps.EvalExpression;
  ABreakpoint.LogResult := AProps.LogResult;
  ABreakpoint.EnableGroup := AProps.EnableGroup;
  ABreakpoint.DisableGroup := AProps.DisableGroup;
  ABreakpoint.DoHandleExceptions := AProps.HandleExceptions;
  ABreakpoint.DoIgnoreExceptions := AProps.IgnoreExceptions;
  ABreakpoint.StackFramesToLog := AProps.StackFrames;
  ABreakpoint.Enabled := AProps.Enabled;
end;

/// <summary>Quelltext-Haltepunkte der IDE und ihre Lage für den Plan.</summary>
function SourceBreakpoints(out APlaces: TAtlasBreakpointPlaces): TArray<IOTABreakpoint>;
var
  mServices: IOTADebuggerServices;
  mIndex, mCount: Integer;
  mBreakpoint: IOTASourceBreakpoint;
begin
  Result := nil;
  APlaces := nil;
  mServices := TAtlasIdeBreakpoints.Debugger;
  if mServices = nil then
  begin
    Exit;
  end;
  SetLength(Result, mServices.SourceBkptCount);
  mCount := 0;
  for mIndex := 0 to mServices.SourceBkptCount - 1 do
  begin
    mBreakpoint := mServices.SourceBkpts[mIndex];
    if (mBreakpoint <> nil) and (mBreakpoint.FileName <> '') and (mBreakpoint.LineNumber > 0) then
    begin
      Result[mCount] := mBreakpoint;
      Inc(mCount);
      APlaces := APlaces + [TAtlasBreakpointPlace.Create(mBreakpoint.FileName, mBreakpoint.LineNumber - 1,
        mBreakpoint.Enabled)];
    end;
  end;
  SetLength(Result, mCount);
end;

function SourceTextFunc: TAtlasBreakpointTextFunc;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := TAtlasIdeFiles.SourceText(AFileName, AText);
    end;
end;

{ TAtlasIdeBreakpointSets }

class procedure TAtlasIdeBreakpointSets.Start(const AMessage: TProc<string>);
var
  mTimer: TTimer;
begin
  FMessage := AMessage;
  FStarted := True;
  mTimer := TTimer.Create(nil);
  mTimer.Interval := cTickMs;
  mTimer.OnTimer := Tick;
  FTimer := mTimer;
end;

class procedure TAtlasIdeBreakpointSets.Release;
begin
  FStarted := False;
  FreeAndNil(FTimer);
  // Ein laufender Auftrag hält die Beobachtung selbst; sie endet mit ihm.
  FWatch := nil;
  FWatchHolder := nil;
  FWatchFolder := '';
  FBusy := False;
  FMessage := nil;
  FreeAndNil(FPlaces);
end;

class function TAtlasIdeBreakpointSets.Started: Boolean;
begin
  Result := FStarted;
end;

class procedure TAtlasIdeBreakpointSets.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class function TAtlasIdeBreakpointSets.ProjectFolder(out AFolder: string): Boolean;
var
  mProject: string;
begin
  mProject := TAtlasIdeFiles.ActiveProjectFile;
  AFolder := ExtractFileDir(mProject);
  Result := AFolder <> '';
end;

class function TAtlasIdeBreakpointSets.LoadSets(const AFolder: string): TAtlasBreakpointSetList;
var
  mFiles: TArray<string>;
  mFile, mJson: string;
  mSet: TAtlasBreakpointSet;
begin
  Result := nil;
  if not TDirectory.Exists(TAtlasBreakpointSets.Folder(AFolder)) then
  begin
    Exit;
  end;
  mFiles := TDirectory.GetFiles(TAtlasBreakpointSets.Folder(AFolder), '*.json');
  TArray.Sort<string>(mFiles);
  for mFile in mFiles do
  begin
    if not TAtlasDataFile.TryRead(mFile, mJson) then
    begin
      Continue;
    end;
    if TAtlasBreakpointSets.Parse(mJson, AFolder, TPath.GetFileNameWithoutExtension(mFile), mSet) then
    begin
      Result := Result + [mSet];
    end
    else
    begin
      Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointSetUnreadable,
        [TPath.GetFileNameWithoutExtension(mFile)]));
    end;
  end;
end;

class function TAtlasIdeBreakpointSets.Capture(out AEntries: TAtlasBreakpointSetEntries): Boolean;
var
  mBreakpoints: TArray<IOTABreakpoint>;
  mPlaces: TAtlasBreakpointPlaces;
  mIndex: Integer;
  mText: string;
begin
  AEntries := nil;
  mBreakpoints := SourceBreakpoints(mPlaces);
  for mIndex := 0 to High(mBreakpoints) do
  begin
    if not TAtlasIdeFiles.SourceText(mPlaces[mIndex].FileName, mText) then
    begin
      mText := '';
    end;
    AEntries := AEntries + [TAtlasBreakpointSets.Capture(mPlaces[mIndex].FileName, mText, mPlaces[mIndex].Line,
      PropsOf(mBreakpoints[mIndex]))];
  end;
  Result := AEntries <> nil;
end;

/// <summary>Einträge aller Sätze außer ASets[AIndex]; nil ohne AExclusive.</summary>
function OthersOf(const ASets: TAtlasBreakpointSetList; AIndex: Integer;
  AExclusive: Boolean): TAtlasBreakpointSetEntries;
var
  mIndex: Integer;
begin
  Result := nil;
  if not AExclusive then
  begin
    Exit;
  end;
  for mIndex := 0 to High(ASets) do
  begin
    if mIndex <> AIndex then
    begin
      Result := Result + ASets[mIndex].Entries;
    end;
  end;
end;

type
  /// <summary>Zähler beim Anwenden eines Satzes.</summary>
  TApplyCounts = record
    Created: Integer;
    Enabled: Integer;
    Disabled: Integer;
  end;

/// <summary>Aktion des Plans an den Haltepunkten der IDE ausführen (Fehlende meldet Apply).</summary>
procedure RunAction(const ABreakpoints: TArray<IOTABreakpoint>; const AAction: TAtlasBreakpointSetAction;
  var ACounts: TApplyCounts);
var
  mNew: IOTABreakpoint;
begin
  case AAction.Kind of
    TAtlasBreakpointSetActionKind.Enable:
      begin
        ABreakpoints[AAction.Index].Enabled := True;
        Inc(ACounts.Enabled);
      end;
    TAtlasBreakpointSetActionKind.Disable:
      begin
        ABreakpoints[AAction.Index].Enabled := False;
        Inc(ACounts.Disabled);
      end;
    TAtlasBreakpointSetActionKind.Create:
      begin
        mNew := TAtlasIdeBreakpoints.Add(AAction.Entry.FileName, AAction.Line);
        if mNew <> nil then
        begin
          ApplyProps(mNew, AAction.Entry.Props);
          Inc(ACounts.Created);
        end;
      end;
  else
    // Missing meldet Apply mit dem Namen des Satzes.
  end;
end;

class procedure TAtlasIdeBreakpointSets.Apply(const ASets: TAtlasBreakpointSetList; AIndex: Integer;
  AExclusive: Boolean; const APrefix: string);
var
  mBreakpoints: TArray<IOTABreakpoint>;
  mPlaces: TAtlasBreakpointPlaces;
  mAction: TAtlasBreakpointSetAction;
  mCounts: TApplyCounts;
  mText: TAtlasBreakpointTextFunc;
begin
  mBreakpoints := SourceBreakpoints(mPlaces);
  mCounts := Default(TApplyCounts);
  mText := SourceTextFunc();
  for mAction in TAtlasBreakpointSets.Plan(mPlaces, TAtlasBreakpointSets.Resolve(ASets[AIndex].Entries, mText),
    TAtlasBreakpointSets.Resolve(OthersOf(ASets, AIndex, AExclusive), mText), AExclusive) do
  begin
    if mAction.Kind = TAtlasBreakpointSetActionKind.Missing then
    begin
      Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointSetMissing, [ASets[AIndex].Name,
        ExtractFileName(mAction.Entry.FileName), mAction.Line + 1, mAction.Entry.Anchor.Method]));
    end
    else
    begin
      RunAction(mBreakpoints, mAction, mCounts);
    end;
  end;
  FActiveName := ASets[AIndex].Name;
  if AExclusive then
  begin
    Report(APrefix + TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointSetSwitched, [ASets[AIndex].Name,
      mCounts.Created, mCounts.Enabled, mCounts.Disabled]));
  end
  else
  begin
    Report(APrefix + TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointSetAdded, [ASets[AIndex].Name,
      mCounts.Created, mCounts.Enabled]));
  end;
end;

class function TAtlasIdeBreakpointSets.Choose(AMode: TAtlasBreakpointSetMode; out AFolder: string;
  out ASets: TAtlasBreakpointSetList; out AIndex: Integer): Boolean;
var
  mName, mBranch: string;
  mIndex: Integer;
begin
  Result := False;
  AIndex := -1;
  ASets := nil;
  if not ProjectFolder(AFolder) then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetNoProject));
    Exit;
  end;
  ASets := LoadSets(AFolder);
  if ASets = nil then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetNone));
    Exit;
  end;
  if not TAtlasBreakpointSetDialog.Execute(AMode, ASets, '', FActiveName, mName,
    mBranch) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(ASets) do
  begin
    if SameText(ASets[mIndex].Name, mName) then
    begin
      AIndex := mIndex;
      Exit(True);
    end;
  end;
end;

class function TAtlasIdeBreakpointSets.AskSet(const AFolder: string; var ASet: TAtlasBreakpointSet): Boolean;
var
  mName, mBranch: string;
  mSets: TAtlasBreakpointSetList;
  mIndex: Integer;
begin
  mSets := LoadSets(AFolder);
  Result := TAtlasBreakpointSetDialog.Execute(TAtlasBreakpointSetMode.Save, mSets, FBranch, FActiveName, mName,
    mBranch);
  if not Result then
  begin
    Exit;
  end;
  Result := TAtlasBreakpointSets.ValidName(mName);
  if not Result then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointSetInvalidName, [mName]));
    Exit;
  end;
  ASet.Name := Trim(mName);
  ASet.Branch := mBranch;
  // Ohne neue Kopplung bleibt der Branch eines vorhandenen Satzes gleichen Namens.
  for mIndex := 0 to High(mSets) do
  begin
    if SameText(mSets[mIndex].Name, ASet.Name) and (ASet.Branch = '') and (FBranch = '') then
    begin
      ASet.Branch := mSets[mIndex].Branch;
    end;
  end;
end;

class function TAtlasIdeBreakpointSets.WriteSet(const AFolder: string; const ASet: TAtlasBreakpointSet): Boolean;
var
  mFile: string;
begin
  mFile := TAtlasBreakpointSets.FileFor(AFolder, ASet.Name);
  try
    ForceDirectories(ExtractFileDir(mFile));
    TAtlasDataFile.Write(mFile, TAtlasBreakpointSets.ToJson(ASet, AFolder));
    Result := True;
  except
    on E: Exception do
    begin
      Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointSetNotSaved, [ASet.Name, E.Message]));
      Result := False;
    end;
  end;
end;

class procedure TAtlasIdeBreakpointSets.SaveSet;
var
  mFolder: string;
  mSet: TAtlasBreakpointSet;
begin
  mSet := Default(TAtlasBreakpointSet);
  if not ProjectFolder(mFolder) then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetNoProject));
  end
  else if not Capture(mSet.Entries) then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetNoBreakpoints));
  end
  else if AskSet(mFolder, mSet) and WriteSet(mFolder, mSet) then
  begin
    FActiveName := mSet.Name;
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointSetSaved, [mSet.Name, Length(mSet.Entries)]));
  end;
end;

class procedure TAtlasIdeBreakpointSets.SwitchSet;
var
  mFolder: string;
  mSets: TAtlasBreakpointSetList;
  mIndex: Integer;
begin
  if Choose(TAtlasBreakpointSetMode.Switch, mFolder, mSets, mIndex) then
  begin
    Apply(mSets, mIndex, True, '');
  end;
end;

class procedure TAtlasIdeBreakpointSets.AddSet;
var
  mFolder: string;
  mSets: TAtlasBreakpointSetList;
  mIndex: Integer;
begin
  if Choose(TAtlasBreakpointSetMode.Add, mFolder, mSets, mIndex) then
  begin
    Apply(mSets, mIndex, False, '');
  end;
end;

class procedure TAtlasIdeBreakpointSets.DeleteSet;
var
  mFolder: string;
  mSets: TAtlasBreakpointSetList;
  mIndex: Integer;
  mFile: string;
begin
  if not Choose(TAtlasBreakpointSetMode.Delete, mFolder, mSets, mIndex) then
  begin
    Exit;
  end;
  mFile := TAtlasBreakpointSets.FileFor(mFolder, mSets[mIndex].Name);
  try
    TFile.Delete(mFile);
  except
    on E: Exception do
    begin
      Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointSetNotSaved, [mSets[mIndex].Name, E.Message]));
      Exit;
    end;
  end;
  if SameText(FActiveName, mSets[mIndex].Name) then
  begin
    FActiveName := '';
  end;
  Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointSetDeleted, [mSets[mIndex].Name]));
end;

{ Branch-Wechsel }

class procedure TAtlasIdeBreakpointSets.BranchArrived(const ABranch: string; ASwitched: Boolean);
var
  mFolder: string;
  mSets: TAtlasBreakpointSetList;
  mIndex: Integer;
begin
  FBranch := ABranch;
  if not ASwitched or not TAtlasIdeSettings.Current.DebugBreakpointSetPerBranch or not ProjectFolder(mFolder) then
  begin
    Exit;
  end;
  mSets := LoadSets(mFolder);
  mIndex := TAtlasBreakpointSets.ForBranch(mSets, ABranch);
  if mIndex >= 0 then
  begin
    Apply(mSets, mIndex, True, TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointSetBranchSwitched,
      [ABranch]));
  end;
end;

class procedure TAtlasIdeBreakpointSets.Tick(Sender: TObject);
var
  mFolder: string;
  mHolder: TWatchHolder;
  mKeep: IInterface;
  mResult: TArray<TAtlasVcsSwitch>;
begin
  if FBusy or not FStarted or not TAtlasIdeSettings.Current.DebugBreakpointSetPerBranch or
    not ProjectFolder(mFolder) then
  begin
    Exit;
  end;
  if (FWatch = nil) or not SameText(FWatchFolder, mFolder) then
  begin
    mHolder := TWatchHolder.Create(mFolder);
    FWatch := mHolder;
    FWatchHolder := mHolder;
    FWatchFolder := mFolder;
  end;
  mKeep := FWatch;
  mHolder := TWatchHolder(FWatchHolder);
  // Ergebnis in einem Array: Hintergrund und Hauptthread teilen es über die gefangene Variable.
  SetLength(mResult, 1);
  mResult[0] := TAtlasVcsSwitch.None;
  FBusy := True;
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      mResult[0] := mHolder.Watch.Check;
    end,
    procedure
    begin
      if not FStarted or (FWatch <> mKeep) then
      begin
        Exit;
      end;
      FBusy := False;
      if mHolder.Watch.Known then
      begin
        BranchArrived(mHolder.Watch.Head.Branch, mResult[0] = TAtlasVcsSwitch.Branch);
      end;
    end) then
  begin
    FBusy := False;
  end;
end;

class procedure TAtlasIdeBreakpointSets.ReadPlaces;
var
  mFolder, mKey: string;
  mSet: TAtlasBreakpointSet;
  mItem: TAtlasResolvedBreakpoint;
  mIndex: Integer;
begin
  if FPlaces = nil then
  begin
    FPlaces := TStringList.Create;
  end;
  FPlaces.Clear;
  FPlacesAt := TThread.GetTickCount64;
  if not ProjectFolder(mFolder) then
  begin
    Exit;
  end;
  for mSet in LoadSets(mFolder) do
  begin
    for mItem in TAtlasBreakpointSets.Resolve(mSet.Entries, SourceTextFunc()) do
    begin
      if not mItem.Found then
      begin
        Continue;
      end;
      mKey := LowerCase(mItem.Entry.FileName) + '|' + IntToStr(mItem.Line);
      mIndex := FPlaces.IndexOfName(mKey);
      if mIndex < 0 then
      begin
        FPlaces.Add(mKey + '=' + mSet.Name);
      end
      else
      begin
        FPlaces.ValueFromIndex[mIndex] := FPlaces.ValueFromIndex[mIndex] + #9 + mSet.Name;
      end;
    end;
  end;
end;

class function TAtlasIdeBreakpointSets.SetNamesAt(const AFileName: string; ALine: Integer): TArray<string>;
var
  mNames: string;
begin
  if (FPlaces = nil) or (TThread.GetTickCount64 - FPlacesAt >= cPlacesMs) then
  begin
    ReadPlaces;
  end;
  mNames := FPlaces.Values[LowerCase(AFileName) + '|' + IntToStr(ALine)];
  Result := nil;
  if mNames <> '' then
  begin
    Result := mNames.Split([#9]);
  end;
end;

end.
