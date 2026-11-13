unit Atlas.Core.Debug.BreakpointCheck;

// Haltepunkte, die nicht greifen werden (#577), Kern ohne IDE:
// - Anfrage an atlas.server.breakpointCheck: die Zeilen der aktiven
//   Quelltext-Haltepunkte je Datei (Arguments), Antwort lesen (ReadAnswer).
//   Der Server ordnet ein: Zeile ohne Code (mit nächster Codezeile), inaktiver
//   Zweig der bedingten Kompilierung, {$D-} aus Unit oder Projekt.
// - „Gehört nicht zum gestarteten Projekt“ entscheidet die IDE-Seite mit
//   NotInProject: Die Datei ist Modul eines anderen Projekts der Gruppe, nicht
//   des gestarteten, und liegt nicht unter dessen Ordner. Units aus Packages
//   und Bibliotheken (RTL, VCL mit Debug-DCUs) meldet Atlas nicht, weil sie zur
//   Laufzeit dazukommen können.
// - Sortiert nach Datei und Zeile; Movable zählt, was sich auf die nächste
//   Codezeile verschieben lässt.

interface

uses
  System.SysUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  TAtlasBreakpointReason = (NoCode, Inactive, NoDebugInfo, NotInProject, Unreadable);
  {$SCOPEDENUMS OFF}

  /// <summary>Ein aktiver Quelltext-Haltepunkt: Datei, URI für den Server und Zeile ab 0.</summary>
  TAtlasBreakpointSpot = record
    FileName: string;
    Uri: string;
    Line: Integer;
    class function Create(const AFileName, AUri: string; ALine: Integer): TAtlasBreakpointSpot; static;
  end;

  TAtlasBreakpointSpots = TArray<TAtlasBreakpointSpot>;

  TAtlasBreakpointProblem = record
    FileName: string;
    /// <summary>Zeile ab 0.</summary>
    Line: Integer;
    Reason: TAtlasBreakpointReason;
    /// <summary>Bedingung des Zweigs, Herkunft von $D- bzw. ''.</summary>
    Detail: string;
    /// <summary>Nächste Zeile mit Code (ab 0) bei NoCode; -1 ohne.</summary>
    NextLine: Integer;
    /// <summary>Lässt sich der Haltepunkt auf die nächste Codezeile verschieben?</summary>
    function CanMove: Boolean;
  end;

  TAtlasBreakpointProblems = TArray<TAtlasBreakpointProblem>;

  TAtlasBreakpointCheck = class
  public const
    cCommand = 'atlas.server.breakpointCheck';
  public
    /// <summary>JSON-Argumente [[{"uri", "lines"}, …]] für Command; Zeilen je Datei zusammengefasst.</summary>
    class function Arguments(const ASpots: TAtlasBreakpointSpots): string; static;
    /// <summary>Antwort von Command lesen; False bei fremdem Format. Dateien ordnet Atlas über die URI den
    /// Haltepunkten aus ASpots zu, fremde URIs fallen weg.</summary>
    class function ReadAnswer(AJson: TJSONValue; const ASpots: TAtlasBreakpointSpots;
      out AProblems: TAtlasBreakpointProblems): Boolean; static;
    /// <summary>Gehört AFileName sicher nicht zum gestarteten Projekt? AInLaunched: Modul des gestarteten
    /// Projekts; AInOther: Modul eines anderen Projekts der Gruppe; ALaunchFolder: Ordner der .dproj.</summary>
    class function NotInProject(const AFileName, ALaunchFolder: string; AInLaunched, AInOther: Boolean): Boolean;
      static;
    /// <summary>Problem für einen Haltepunkt außerhalb des Projekts.</summary>
    class function NotInProjectProblem(const ASpot: TAtlasBreakpointSpot): TAtlasBreakpointProblem; static;
    /// <summary>Nach Datei (ohne Groß-/Kleinschreibung) und Zeile; je Stelle nur das erste Problem.</summary>
    class function Sorted(const AProblems: TAtlasBreakpointProblems): TAtlasBreakpointProblems; static;
    /// <summary>Anzahl der Probleme mit CanMove.</summary>
    class function Movable(const AProblems: TAtlasBreakpointProblems): Integer; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults;

const
  cFormat = 1;

{ TAtlasBreakpointSpot }

class function TAtlasBreakpointSpot.Create(const AFileName, AUri: string; ALine: Integer): TAtlasBreakpointSpot;
begin
  Result.FileName := AFileName;
  Result.Uri := AUri;
  Result.Line := ALine;
end;

{ TAtlasBreakpointProblem }

function TAtlasBreakpointProblem.CanMove: Boolean;
begin
  Result := (Reason = TAtlasBreakpointReason.NoCode) and (NextLine > Line);
end;

{ TAtlasBreakpointCheck }

class function TAtlasBreakpointCheck.Arguments(const ASpots: TAtlasBreakpointSpots): string;
var
  mRoot, mFiles, mLines: TJSONArray;
  mByUri: TDictionary<string, TJSONArray>;
  mSpot: TAtlasBreakpointSpot;
  mFile: TJSONObject;
begin
  mRoot := TJSONArray.Create;
  mByUri := TDictionary<string, TJSONArray>.Create;
  try
    mFiles := TJSONArray.Create;
    mRoot.AddElement(mFiles);
    for mSpot in ASpots do
    begin
      if not mByUri.TryGetValue(mSpot.Uri, mLines) then
      begin
        mFile := TJSONObject.Create;
        mFile.AddPair('uri', mSpot.Uri);
        mLines := TJSONArray.Create;
        mFile.AddPair('lines', mLines);
        mFiles.AddElement(mFile);
        mByUri.Add(mSpot.Uri, mLines);
      end;
      mLines.Add(mSpot.Line);
    end;
    Result := mRoot.ToJSON;
  finally
    mByUri.Free;
    mRoot.Free;
  end;
end;

function ReasonOf(const AName: string; out AReason: TAtlasBreakpointReason): Boolean;
begin
  Result := True;
  if AName = 'noCode' then
  begin
    AReason := TAtlasBreakpointReason.NoCode;
  end
  else if AName = 'inactive' then
  begin
    AReason := TAtlasBreakpointReason.Inactive;
  end
  else if AName = 'noDebugInfo' then
  begin
    AReason := TAtlasBreakpointReason.NoDebugInfo;
  end
  else
  begin
    AReason := TAtlasBreakpointReason.NoCode;
    Result := False;
  end;
end;

function FileOfUri(const ASpots: TAtlasBreakpointSpots; const AUri: string; out AFileName: string): Boolean;
var
  mSpot: TAtlasBreakpointSpot;
begin
  for mSpot in ASpots do
  begin
    if SameText(mSpot.Uri, AUri) then
    begin
      AFileName := mSpot.FileName;
      Exit(True);
    end;
  end;
  AFileName := '';
  Result := False;
end;

/// <summary>Ein Eintrag aus "items"; False bei unbekanntem Grund oder ohne Zeile.</summary>
function ReadItem(AItem: TJSONValue; const AFileName: string; out AProblem: TAtlasBreakpointProblem): Boolean;
var
  mItem: TJSONObject;
begin
  AProblem := Default(TAtlasBreakpointProblem);
  Result := False;
  if not (AItem is TJSONObject) then
  begin
    Exit;
  end;
  mItem := TJSONObject(AItem);
  if not ReasonOf(mItem.GetValue<string>('reason', ''), AProblem.Reason) then
  begin
    Exit;
  end;
  AProblem.FileName := AFileName;
  AProblem.Line := mItem.GetValue<Integer>('line', -1);
  AProblem.Detail := mItem.GetValue<string>('detail', '');
  AProblem.NextLine := mItem.GetValue<Integer>('nextLine', -1);
  Result := AProblem.Line >= 0;
end;

/// <summary>Probleme einer Datei aus "files" an AProblems anhängen.</summary>
procedure ReadFile(AFile: TJSONValue; const ASpots: TAtlasBreakpointSpots; var AProblems: TAtlasBreakpointProblems);
var
  mFile: TJSONObject;
  mFileName: string;
  mItems: TJSONValue;
  mItem: TJSONValue;
  mProblem: TAtlasBreakpointProblem;
  mSpot: TAtlasBreakpointSpot;
begin
  if not (AFile is TJSONObject) then
  begin
    Exit;
  end;
  mFile := TJSONObject(AFile);
  if not FileOfUri(ASpots, mFile.GetValue<string>('uri', ''), mFileName) then
  begin
    Exit;
  end;
  if mFile.GetValue<Boolean>('unreadable', False) then
  begin
    for mSpot in ASpots do
    begin
      if SameText(mSpot.FileName, mFileName) then
      begin
        mProblem := Default(TAtlasBreakpointProblem);
        mProblem.FileName := mFileName;
        mProblem.Line := mSpot.Line;
        mProblem.Reason := TAtlasBreakpointReason.Unreadable;
        mProblem.NextLine := -1;
        AProblems := AProblems + [mProblem];
      end;
    end;
    Exit;
  end;
  mItems := mFile.GetValue('items');
  if not (mItems is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mItems) do
  begin
    if ReadItem(mItem, mFileName, mProblem) then
    begin
      AProblems := AProblems + [mProblem];
    end;
  end;
end;

class function TAtlasBreakpointCheck.ReadAnswer(AJson: TJSONValue; const ASpots: TAtlasBreakpointSpots;
  out AProblems: TAtlasBreakpointProblems): Boolean;
var
  mRoot: TJSONObject;
  mFiles: TJSONValue;
  mFile: TJSONValue;
begin
  AProblems := nil;
  Result := False;
  if not (AJson is TJSONObject) then
  begin
    Exit;
  end;
  mRoot := TJSONObject(AJson);
  mFiles := mRoot.GetValue('files');
  if (mRoot.GetValue<Integer>('format', 0) <> cFormat) or not (mFiles is TJSONArray) then
  begin
    Exit;
  end;
  for mFile in TJSONArray(mFiles) do
  begin
    ReadFile(mFile, ASpots, AProblems);
  end;
  Result := True;
end;

class function TAtlasBreakpointCheck.NotInProject(const AFileName, ALaunchFolder: string; AInLaunched,
  AInOther: Boolean): Boolean;
var
  mFolder: string;
begin
  Result := False;
  if AInLaunched or not AInOther or (AFileName = '') then
  begin
    Exit;
  end;
  // Beide Trenner gleich behandeln (Pfade aus der IDE und aus URIs).
  mFolder := ALaunchFolder.Replace('\', '/');
  if mFolder <> '' then
  begin
    if not mFolder.EndsWith('/') then
    begin
      mFolder := mFolder + '/';
    end;
    // Unter dem Ordner des gestarteten Projekts kann die Unit über den Suchpfad dazugehören.
    if SameText(Copy(AFileName.Replace('\', '/'), 1, Length(mFolder)), mFolder) then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

class function TAtlasBreakpointCheck.NotInProjectProblem(const ASpot: TAtlasBreakpointSpot): TAtlasBreakpointProblem;
begin
  Result := Default(TAtlasBreakpointProblem);
  Result.FileName := ASpot.FileName;
  Result.Line := ASpot.Line;
  Result.Reason := TAtlasBreakpointReason.NotInProject;
  Result.NextLine := -1;
end;

class function TAtlasBreakpointCheck.Sorted(const AProblems: TAtlasBreakpointProblems): TAtlasBreakpointProblems;
var
  mList: TList<TAtlasBreakpointProblem>;
  mProblem: TAtlasBreakpointProblem;
  mLast: TAtlasBreakpointProblem;
  mHasLast: Boolean;
begin
  mList := TList<TAtlasBreakpointProblem>.Create(TComparer<TAtlasBreakpointProblem>.Construct(
    function(const ALeft, ARight: TAtlasBreakpointProblem): Integer
    begin
      Result := CompareText(ALeft.FileName, ARight.FileName);
      if Result = 0 then
      begin
        Result := ALeft.Line - ARight.Line;
      end;
      if Result = 0 then
      begin
        // Eindeutig weitersortieren: TList.Sort ist nicht stabil.
        Result := Ord(ALeft.Reason) - Ord(ARight.Reason);
      end;
    end));
  try
    mList.AddRange(AProblems);
    mList.Sort;
    Result := nil;
    mHasLast := False;
    mLast := Default(TAtlasBreakpointProblem);
    for mProblem in mList do
    begin
      if mHasLast and SameText(mProblem.FileName, mLast.FileName) and (mProblem.Line = mLast.Line) then
      begin
        Continue;
      end;
      Result := Result + [mProblem];
      mLast := mProblem;
      mHasLast := True;
    end;
  finally
    mList.Free;
  end;
end;

class function TAtlasBreakpointCheck.Movable(const AProblems: TAtlasBreakpointProblems): Integer;
var
  mProblem: TAtlasBreakpointProblem;
begin
  Result := 0;
  for mProblem in AProblems do
  begin
    if mProblem.CanMove then
    begin
      Inc(Result);
    end;
  end;
end;

end.
