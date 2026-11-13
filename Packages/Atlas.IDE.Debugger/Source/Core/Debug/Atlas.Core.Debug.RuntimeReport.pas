unit Atlas.Core.Debug.RuntimeReport;

// Leck- und Absturzberichte im Editor (#74), ohne VCL und Open Tools API: Argumente für die Befehle
// atlas.server.runtimeReport und .clear und die Antwort als Records. Der Server löst den Bericht auf und hängt
// die Diagnosen an; das Plugin zeigt die Stapel in der Meldungsansicht mit anklickbaren Zeilen.
//
// Antwort des Servers (Atlas.Common.Lsp.RuntimeReport):
//   { kind: "leaks" | "crash" | "none", source, title, mapStatus, map, diagnostics,
//     crash?: {exceptionClass, message, address, module},
//     groups?: [{name, kind, count, size, site, frames}], threads?: [{name, crashed, site, frames}] }
//   frame = {address, module, unit, routine, line, uri?, file?}

interface

uses
  System.SysUtils,
  System.JSON;

type
{$SCOPEDENUMS ON}
  TAtlasRuntimeReportKind = (None, Leaks, Crash);
  /// <summary>Stand der Map: keine, fehlt, ohne EXE nicht geprüft, passt, passt nicht.</summary>
  TAtlasRuntimeMapStatus = (None, Missing, Unchecked, Matches, Differs);
{$SCOPEDENUMS OFF}

  TAtlasRuntimeFrame = record
    /// <summary>Hex mit $ oder ''.</summary>
    Address: string;
    Module: string;
    UnitName: string;
    Routine: string;
    /// <summary>Zeile ab 1; 0 ohne.</summary>
    Line: Integer;
    /// <summary>Datei im Projekt; '' außerhalb.</summary>
    FileName: string;
    /// <summary>„Unit.Routine“, ohne doppelten Unitnamen; sonst Adresse und Modul.</summary>
    function Location: string;
  end;

  /// <summary>Leckgruppe bzw. Thread.</summary>
  TAtlasRuntimeStack = record
    Name: string;
    /// <summary>Nur Lecks: instance, string, unknown.</summary>
    LeakKind: string;
    Count: Integer;
    Size: Int64;
    Crashed: Boolean;
    /// <summary>Index der Erzeugungs- bzw. Absturzstelle in Frames; -1 ohne.</summary>
    Site: Integer;
    Frames: TArray<TAtlasRuntimeFrame>;
  end;

  TAtlasRuntimeReport = record
    Kind: TAtlasRuntimeReportKind;
    Source: string;
    Title: string;
    MapStatus: TAtlasRuntimeMapStatus;
    MapName: string;
    /// <summary>Zahl der Diagnosen, die der Server an Stellen im Projekt gehängt hat.</summary>
    Diagnostics: Integer;
    ExceptionClass: string;
    ExceptionMessage: string;
    Address: string;
    Module: string;
    Stacks: TArray<TAtlasRuntimeStack>;
  end;

  TAtlasRuntimeReports = class
  public const
    cCommand = 'atlas.server.runtimeReport';
    cClearCommand = 'atlas.server.runtimeReport.clear';
  public
    /// <summary>[uri, {text}] für den Bericht AText zum Projekt AProject.</summary>
    class function ArgumentsJson(const AProject, AText: string): string; static;
    /// <summary>[uri] zum Leeren.</summary>
    class function ClearArgumentsJson(const AProject: string): string; static;
    /// <summary>Antwort des Servers; False bei unlesbarer Antwort.</summary>
    class function FromJson(const AJson: string; out AReport: TAtlasRuntimeReport): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Json,
  Atlas.Core.Lsp.Uris;

const
  cMapNames: array[TAtlasRuntimeMapStatus] of string = ('none', 'missing', 'unchecked', 'matches', '');
  cKindNames: array[TAtlasRuntimeReportKind] of string = ('none', 'leaks', 'crash');

{ TAtlasRuntimeFrame }

function TAtlasRuntimeFrame.Location: string;
begin
  Result := Routine;
  if (UnitName <> '') and (Routine = '') then
  begin
    Result := UnitName;
  end
  else if (UnitName <> '') and not StartsText(UnitName + '.', Routine) then
  begin
    Result := UnitName + '.' + Routine;
  end;
  if Result = '' then
  begin
    Result := Trim(Address + ' ' + Module);
  end;
end;

{ Lesen }

function MapStatusOf(const AName: string): TAtlasRuntimeMapStatus;
var
  mStatus: TAtlasRuntimeMapStatus;
begin
  for mStatus := Low(TAtlasRuntimeMapStatus) to High(TAtlasRuntimeMapStatus) do
  begin
    if (cMapNames[mStatus] <> '') and SameText(AName, cMapNames[mStatus]) then
    begin
      Exit(mStatus);
    end;
  end;
  // entryPointDiffers, codeSizeDiffers
  Result := TAtlasRuntimeMapStatus.Differs;
  if AName = '' then
  begin
    Result := TAtlasRuntimeMapStatus.None;
  end;
end;

function KindOf(const AName: string): TAtlasRuntimeReportKind;
var
  mKind: TAtlasRuntimeReportKind;
begin
  for mKind := Low(TAtlasRuntimeReportKind) to High(TAtlasRuntimeReportKind) do
  begin
    if SameText(AName, cKindNames[mKind]) then
    begin
      Exit(mKind);
    end;
  end;
  Result := TAtlasRuntimeReportKind.None;
end;

function FrameOf(AObject: TJSONObject): TAtlasRuntimeFrame;
begin
  Result := Default(TAtlasRuntimeFrame);
  Result.Address := TJsonRead.Text(AObject, 'address');
  Result.Module := TJsonRead.Text(AObject, 'module');
  Result.UnitName := TJsonRead.Text(AObject, 'unit');
  Result.Routine := TJsonRead.Text(AObject, 'routine');
  Result.Line := TJsonRead.IntOr(AObject, 'line', 0);
  Result.FileName := TJsonRead.Text(AObject, 'file');
end;

function StackOf(AObject: TJSONObject): TAtlasRuntimeStack;
var
  mFrames: TJSONArray;
  mItem: TJSONValue;
begin
  Result := Default(TAtlasRuntimeStack);
  Result.Name := TJsonRead.Text(AObject, 'name');
  Result.LeakKind := TJsonRead.Text(AObject, 'kind');
  Result.Count := TJsonRead.IntOr(AObject, 'count', 0);
  Result.Size := TJsonRead.Int64Or(AObject, 'size', 0);
  Result.Crashed := TJsonRead.Flag(AObject, 'crashed');
  Result.Site := TJsonRead.IntOr(AObject, 'site', -1);
  mFrames := TJsonRead.Items(AObject, 'frames');
  if mFrames <> nil then
  begin
    for mItem in mFrames do
    begin
      if mItem is TJSONObject then
      begin
        Result.Frames := Result.Frames + [FrameOf(TJSONObject(mItem))];
      end;
    end;
  end;
  if Result.Site >= Length(Result.Frames) then
  begin
    Result.Site := -1;
  end;
end;

function StacksOf(AItems: TJSONArray): TArray<TAtlasRuntimeStack>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if AItems = nil then
  begin
    Exit;
  end;
  for mItem in AItems do
  begin
    if mItem is TJSONObject then
    begin
      Result := Result + [StackOf(TJSONObject(mItem))];
    end;
  end;
end;

class function TAtlasRuntimeReports.FromJson(const AJson: string; out AReport: TAtlasRuntimeReport): Boolean;
var
  mRoot, mCrash: TJSONObject;
begin
  AReport := Default(TAtlasRuntimeReport);
  mRoot := TJsonRead.ParseObject(AJson);
  Result := (mRoot <> nil) and (TJsonRead.Value(mRoot, 'kind') <> nil);
  if not Result then
  begin
    mRoot.Free;
    Exit;
  end;
  try
    AReport.Kind := KindOf(TJsonRead.Text(mRoot, 'kind'));
    AReport.Source := TJsonRead.Text(mRoot, 'source');
    AReport.Title := TJsonRead.Text(mRoot, 'title');
    AReport.MapStatus := MapStatusOf(TJsonRead.Text(mRoot, 'mapStatus'));
    AReport.MapName := TJsonRead.Text(mRoot, 'map');
    AReport.Diagnostics := TJsonRead.IntOr(mRoot, 'diagnostics', 0);
    mCrash := TJsonRead.Obj(mRoot, 'crash');
    AReport.ExceptionClass := TJsonRead.Text(mCrash, 'exceptionClass');
    AReport.ExceptionMessage := TJsonRead.Text(mCrash, 'message');
    AReport.Address := TJsonRead.Text(mCrash, 'address');
    AReport.Module := TJsonRead.Text(mCrash, 'module');
    if AReport.Kind = TAtlasRuntimeReportKind.Crash then
    begin
      AReport.Stacks := StacksOf(TJsonRead.Items(mRoot, 'threads'));
    end
    else
    begin
      AReport.Stacks := StacksOf(TJsonRead.Items(mRoot, 'groups'));
    end;
  finally
    mRoot.Free;
  end;
end;

{ Argumente }

class function TAtlasRuntimeReports.ArgumentsJson(const AProject, AText: string): string;
var
  mArguments: TJSONArray;
  mOptions: TJSONObject;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(TLspUris.FromPath(AProject));
    mOptions := TJSONObject.Create;
    mOptions.AddPair('text', AText);
    mArguments.AddElement(mOptions);
    Result := mArguments.ToJSON;
  finally
    mArguments.Free;
  end;
end;

class function TAtlasRuntimeReports.ClearArgumentsJson(const AProject: string): string;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(TLspUris.FromPath(AProject));
    Result := mArguments.ToJSON;
  finally
    mArguments.Free;
  end;
end;

end.
