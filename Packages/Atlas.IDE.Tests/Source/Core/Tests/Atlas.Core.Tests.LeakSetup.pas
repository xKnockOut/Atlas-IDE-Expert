unit Atlas.Core.Tests.LeakSetup;

// Dialog „Leckprüfung einrichten …“ (#1880) ohne VCL und Open Tools API: die
// Antwort von atlas.server.leakSetup lesen, daraus die Zeilen des Stands
// (✓/✗ je Punkt) und die möglichen Varianten bestimmen, den Plan lesen und
// die fehlenden Symbole in DCC_Define der Konfiguration Debug einfügen.
// Texte setzt die Oberfläche je Zeilenart ein.

interface

uses
  System.SysUtils,
  System.JSON;

type
{$SCOPEDENUMS ON}
  /// <summary>Variante: Einfach = Speichermanager der RTL.</summary>
  TAtlasLeakChoice = (Simple, FastMM4, FastMM5);
  /// <summary>Art einer Zeile im Stand.</summary>
  TAtlasLeakLine = (Package, Source4, Source5, UsesUnit, UsesNotFirst, UsesNotDebug, Report, ReportNotDebug,
    DebugDefine, FileReport, Dll, TestProject, LeakMonitor);
{$SCOPEDENUMS OFF}

  TAtlasLeakSource = record
    FileName: string;
    Version: string;
    OptionsFile: string;
  end;

  /// <summary>Eine Zeile im Stand: erfüllt oder nicht, mit Wert für den Text.</summary>
  TAtlasLeakStatus = record
    Line: TAtlasLeakLine;
    Ok: Boolean;
    Value: string;
  end;

  /// <summary>Antwort von atlas.server.leakSetup ohne Plan.</summary>
  TAtlasLeakSetupInfo = record
    Project: string;
    MainSource: string;
    Platform: string;
    IsPackage: Boolean;
    IsTestProject: Boolean;
    LeakMonitor: string;
    HasUses: Boolean;
    HasMainBlock: Boolean;
    Sources: array[TAtlasLeakChoice] of TAtlasLeakSource;
    /// <summary>Speichermanager im uses; Simple = keiner.</summary>
    UsesManager: TAtlasLeakChoice;
    UsesFirst: Boolean;
    UsesDebugOnly: Boolean;
    ReportLine: Integer;
    ReportDebugOnly: Boolean;
    DebugDefine: Boolean;
    FileReport: Boolean;
    DllName: string;
    DllFile: string;
    DllSource: string;
    DllTarget: string;
    /// <summary>False, wenn AJson keine passende Antwort ist.</summary>
    class function FromJson(const AJson: string; out AInfo: TAtlasLeakSetupInfo): Boolean; static;
    class function FromObject(AObject: TJSONObject): TAtlasLeakSetupInfo; static;
    /// <summary>Lässt sich die Variante einrichten (Quelle gefunden, Hauptblock und uses, kein anderer
    /// Speichermanager schon im uses)?</summary>
    function Available(AChoice: TAtlasLeakChoice): Boolean;
    /// <summary>Vorauswahl: der eingebundene, sonst FastMM5 vor FastMM4 vor Einfach.</summary>
    function Preselect: TAtlasLeakChoice;
    /// <summary>Zeilen des Stands in fester Reihenfolge.</summary>
    function Status: TArray<TAtlasLeakStatus>;
  end;

  /// <summary>Plan aus der Antwort mit zweitem Argument.</summary>
  TAtlasLeakSetupPlan = record
    Choice: TAtlasLeakChoice;
    FileReport: Boolean;
    /// <summary>WorkspaceEdit als JSON-Text.</summary>
    EditJson: string;
    Defines: TArray<string>;
    CopyDll: Boolean;
    Empty: Boolean;
    /// <summary>False ohne „plan“ in AJson.</summary>
    class function FromJson(const AJson: string; out APlan: TAtlasLeakSetupPlan): Boolean; static;
  end;

  TAtlasLeakSetup = class
  public const
    cCommand = 'atlas.server.leakSetup';
    cDebugConfiguration = 'Debug';
    cDefineOption = 'DCC_Define';
    cChoiceNames: array[TAtlasLeakChoice] of string = ('none', 'fastmm4', 'fastmm5');
  public
    /// <summary>Argumente: [uri] bzw. mit Wunsch [uri, {manager, fileReport}].</summary>
    class function ArgumentsJson(const AProject: string; AWithPlan: Boolean; AChoice: TAtlasLeakChoice;
      AFileReport: Boolean): string; static;
    /// <summary>ARaw (DCC_Define ohne Erbe, durch ; getrennt) mit den fehlenden AAdd; ein $(DCC_Define) bleibt
    /// hinten.</summary>
    class function WithDefines(const ARaw: string; const AAdd: TArray<string>): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Json,
  Atlas.Core.Lsp.Uris;

function ChoiceOf(const AName: string): TAtlasLeakChoice;
var
  mChoice: TAtlasLeakChoice;
begin
  for mChoice := Low(TAtlasLeakChoice) to High(TAtlasLeakChoice) do
  begin
    if SameText(AName, TAtlasLeakSetup.cChoiceNames[mChoice]) then
    begin
      Exit(mChoice);
    end;
  end;
  Result := TAtlasLeakChoice.Simple;
end;

function SourceOf(AObject: TJSONObject): TAtlasLeakSource;
begin
  Result := Default(TAtlasLeakSource);
  Result.FileName := TJsonRead.Text(AObject, 'file');
  Result.Version := TJsonRead.Text(AObject, 'version');
  Result.OptionsFile := TJsonRead.Text(AObject, 'optionsFile');
end;

{ TAtlasLeakSetupInfo }

class function TAtlasLeakSetupInfo.FromObject(AObject: TJSONObject): TAtlasLeakSetupInfo;
var
  mUses, mReport, mDll: TJSONObject;
begin
  Result := Default(TAtlasLeakSetupInfo);
  Result.Project := TJsonRead.Text(AObject, 'project');
  Result.MainSource := TJsonRead.Text(AObject, 'mainSource');
  Result.Platform := TJsonRead.Text(AObject, 'platform');
  Result.IsPackage := TJsonRead.Flag(AObject, 'isPackage');
  Result.IsTestProject := TJsonRead.Flag(AObject, 'isTestProject');
  Result.LeakMonitor := TJsonRead.Text(AObject, 'leakMonitor');
  Result.HasUses := TJsonRead.Flag(AObject, 'hasUses');
  Result.HasMainBlock := TJsonRead.Flag(AObject, 'hasMainBlock');
  Result.Sources[TAtlasLeakChoice.FastMM4] := SourceOf(TJsonRead.Obj(AObject, 'fastmm4'));
  Result.Sources[TAtlasLeakChoice.FastMM5] := SourceOf(TJsonRead.Obj(AObject, 'fastmm5'));
  mUses := TJsonRead.Obj(AObject, 'uses');
  Result.UsesManager := ChoiceOf(TJsonRead.Text(mUses, 'manager'));
  Result.UsesFirst := TJsonRead.Flag(mUses, 'first');
  Result.UsesDebugOnly := TJsonRead.Flag(mUses, 'debugOnly');
  mReport := TJsonRead.Obj(AObject, 'report');
  Result.ReportLine := TJsonRead.Int(mReport, 'line');
  Result.ReportDebugOnly := TJsonRead.Flag(mReport, 'debugOnly');
  Result.DebugDefine := TJsonRead.Flag(AObject, 'debugDefine');
  Result.FileReport := TJsonRead.Flag(AObject, 'fileReport');
  mDll := TJsonRead.Obj(AObject, 'dll');
  Result.DllName := TJsonRead.Text(mDll, 'name');
  Result.DllFile := TJsonRead.Text(mDll, 'file');
  Result.DllSource := TJsonRead.Text(mDll, 'source');
  Result.DllTarget := TJsonRead.Text(mDll, 'target');
end;

class function TAtlasLeakSetupInfo.FromJson(const AJson: string; out AInfo: TAtlasLeakSetupInfo): Boolean;
var
  mValue: TJSONValue;
begin
  AInfo := Default(TAtlasLeakSetupInfo);
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := (mValue is TJSONObject) and (TJSONObject(mValue).GetValue('mainSource') is TJSONString);
    if Result then
    begin
      AInfo := FromObject(TJSONObject(mValue));
    end;
  finally
    mValue.Free;
  end;
end;

function TAtlasLeakSetupInfo.Available(AChoice: TAtlasLeakChoice): Boolean;
begin
  Result := not IsPackage and HasMainBlock;
  if Result and (AChoice <> TAtlasLeakChoice.Simple) then
  begin
    Result := (Sources[AChoice].FileName <> '') and HasUses and
      ((UsesManager = TAtlasLeakChoice.Simple) or (UsesManager = AChoice));
  end;
end;

function TAtlasLeakSetupInfo.Preselect: TAtlasLeakChoice;
begin
  if UsesManager <> TAtlasLeakChoice.Simple then
  begin
    Result := UsesManager;
  end
  else if Available(TAtlasLeakChoice.FastMM5) then
  begin
    Result := TAtlasLeakChoice.FastMM5;
  end
  else if Available(TAtlasLeakChoice.FastMM4) then
  begin
    Result := TAtlasLeakChoice.FastMM4;
  end
  else
  begin
    Result := TAtlasLeakChoice.Simple;
  end;
end;

function StatusLine(ALine: TAtlasLeakLine; AOk: Boolean; const AValue: string): TAtlasLeakStatus;
begin
  Result.Line := ALine;
  Result.Ok := AOk;
  Result.Value := AValue;
end;

function SourceText(const ASource: TAtlasLeakSource): string;
begin
  Result := ASource.FileName;
  if ASource.Version <> '' then
  begin
    Result := ASource.Version + ' · ' + Result;
  end;
end;

function UsesLines(const AInfo: TAtlasLeakSetupInfo): TArray<TAtlasLeakStatus>;
var
  mName: string;
begin
  mName := '';
  if AInfo.UsesManager <> TAtlasLeakChoice.Simple then
  begin
    mName := AInfo.Sources[AInfo.UsesManager].FileName;
    mName := ChangeFileExt(ExtractFileName(StringReplace(mName, '\', '/', [rfReplaceAll])), '');
    if mName = '' then
    begin
      mName := IfThen(AInfo.UsesManager = TAtlasLeakChoice.FastMM4, 'FastMM4', 'FastMM5');
    end;
  end;
  Result := [StatusLine(TAtlasLeakLine.UsesUnit, mName <> '', mName)];
  if mName = '' then
  begin
    Exit;
  end;
  if not AInfo.UsesFirst then
  begin
    Result := Result + [StatusLine(TAtlasLeakLine.UsesNotFirst, False, mName)];
  end;
  if not AInfo.UsesDebugOnly then
  begin
    Result := Result + [StatusLine(TAtlasLeakLine.UsesNotDebug, False, mName)];
  end;
  Result := Result + [StatusLine(TAtlasLeakLine.DebugDefine, AInfo.DebugDefine, mName)];
end;

function TAtlasLeakSetupInfo.Status: TArray<TAtlasLeakStatus>;
begin
  if IsPackage then
  begin
    Result := [StatusLine(TAtlasLeakLine.Package, False, ExtractFileName(MainSource))];
    Exit;
  end;
  Result := [
    StatusLine(TAtlasLeakLine.Source4, Sources[TAtlasLeakChoice.FastMM4].FileName <> '',
      SourceText(Sources[TAtlasLeakChoice.FastMM4])),
    StatusLine(TAtlasLeakLine.Source5, Sources[TAtlasLeakChoice.FastMM5].FileName <> '',
      SourceText(Sources[TAtlasLeakChoice.FastMM5]))];
  Result := Result + UsesLines(Self);
  Result := Result + [StatusLine(TAtlasLeakLine.Report, ReportLine > 0, IntToStr(ReportLine))];
  if (ReportLine > 0) and not ReportDebugOnly then
  begin
    Result := Result + [StatusLine(TAtlasLeakLine.ReportNotDebug, False, IntToStr(ReportLine))];
  end;
  Result := Result + [StatusLine(TAtlasLeakLine.FileReport, FileReport, ''),
    StatusLine(TAtlasLeakLine.Dll, DllFile <> '', IfThen(DllFile <> '', DllFile, DllName))];
  if IsTestProject then
  begin
    Result := Result + [StatusLine(TAtlasLeakLine.LeakMonitor, LeakMonitor <> '', LeakMonitor)];
  end;
end;

{ TAtlasLeakSetupPlan }

class function TAtlasLeakSetupPlan.FromJson(const AJson: string; out APlan: TAtlasLeakSetupPlan): Boolean;
var
  mValue: TJSONValue;
  mPlan: TJSONObject;
  mItem: TJSONValue;
begin
  APlan := Default(TAtlasLeakSetupPlan);
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    mPlan := nil;
    if mValue is TJSONObject then
    begin
      mPlan := TJsonRead.Obj(TJSONObject(mValue), 'plan');
    end;
    Result := mPlan <> nil;
    if not Result then
    begin
      Exit;
    end;
    APlan.Choice := ChoiceOf(TJsonRead.Text(mPlan, 'manager'));
    APlan.FileReport := TJsonRead.Flag(mPlan, 'fileReport');
    if mPlan.GetValue('edit') <> nil then
    begin
      APlan.EditJson := mPlan.GetValue('edit').ToJSON;
    end;
    if mPlan.GetValue('defines') is TJSONArray then
    begin
      for mItem in TJSONArray(mPlan.GetValue('defines')) do
      begin
        APlan.Defines := APlan.Defines + [mItem.Value];
      end;
    end;
    APlan.CopyDll := TJsonRead.Flag(mPlan, 'copyDll');
    APlan.Empty := TJsonRead.Flag(mPlan, 'empty');
  finally
    mValue.Free;
  end;
end;

{ TAtlasLeakSetup }

class function TAtlasLeakSetup.ArgumentsJson(const AProject: string; AWithPlan: Boolean; AChoice: TAtlasLeakChoice;
  AFileReport: Boolean): string;
var
  mArguments: TJSONArray;
  mWish: TJSONObject;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(TLspUris.FromPath(AProject));
    if AWithPlan then
    begin
      mWish := TJSONObject.Create;
      mWish.AddPair('manager', cChoiceNames[AChoice]);
      mWish.AddPair('fileReport', TJSONBool.Create(AFileReport));
      mArguments.AddElement(mWish);
    end;
    Result := mArguments.ToJSON;
  finally
    mArguments.Free;
  end;
end;

class function TAtlasLeakSetup.WithDefines(const ARaw: string; const AAdd: TArray<string>): string;
var
  mItems, mKept: TArray<string>;
  mItem, mAdd: string;
  mInherited: Boolean;
begin
  mItems := ARaw.Split([';']);
  mKept := nil;
  mInherited := False;
  for mItem in mItems do
  begin
    if SameText(Trim(mItem), '$(DCC_Define)') then
    begin
      mInherited := True;
    end
    else if Trim(mItem) <> '' then
    begin
      mKept := mKept + [Trim(mItem)];
    end;
  end;
  for mAdd in AAdd do
  begin
    if IndexText(mAdd, mKept) < 0 then
    begin
      mKept := mKept + [mAdd];
    end;
  end;
  if mInherited then
  begin
    mKept := mKept + ['$(DCC_Define)'];
  end;
  Result := string.Join(';', mKept);
end;

end.
