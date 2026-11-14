unit Atlas.Common.Monitor.Results;

// Ergebnisse des Prüffensters von AtlasMonitor (#1900): liest die SARIF-Ausgabe eines Laufs (Pfade über
// originalUriBaseIds aufgelöst, Treffer aus der Baseline übergangen), filtert die Befundliste nach Text und Schwere,
// führt die SARIF-Dateien aller Ziele zu einer zusammen (je Ziel ein Lauf in "runs") und schreibt die Befunde als
// eigenständige HTML-Seite. Ohne VCL und Windows.

interface

uses
  System.SysUtils,
  Atlas.Common.Monitor.Runs;

type
  TMonitorResults = record
  public
    /// <summary>Befunde aus dem SARIF-Text eines Laufs über ATarget; False mit AError bei ungültigem Text.</summary>
    class function ParseSarif(const AText, ATarget: string; out AFindings: TArray<TMonitorFinding>;
      out AError: string): Boolean; static;
    /// <summary>Befunde ab ALevel (error, warning, note; '' = alle), die AText in Datei, Regel oder Meldung
    /// enthalten (ohne Groß-/Kleinschreibung; '' = alle).</summary>
    class function Filter(const AFindings: TArray<TMonitorFinding>; const AText, ALevel: string):
      TArray<TMonitorFinding>; static;
    /// <summary>Eine SARIF-Datei aus mehreren: alle "runs" hintereinander; ungültige Texte werden übergangen.
    /// </summary>
    class function MergeSarif(const ATexts: TArray<string>): string; static;
    /// <summary>Eigenständige HTML-Seite mit allen Befunden, gruppiert nach Ziel, in der aktuellen Sprache.</summary>
    class function Html(const AFindings: TArray<TMonitorFinding>; const ATitle: string): string; static;
    /// <summary>Schwere in der aktuellen Sprache: Fehler, Warnung, Hinweis.</summary>
    class function LevelText(const ALevel: string): string; static;
    /// <summary>Spaltenköpfe der Befundliste: Schwere, Datei, Zeile, Regel, Meldung, Ziel.</summary>
    class function ColumnTitles: TArray<string>; static;
    class function Columns(const AFinding: TMonitorFinding): TArray<string>; static;
  end;

implementation

uses
  System.JSON,
  Atlas.Text.Json,
  Atlas.Text.Uris,
  Atlas.Common.Localization.Texts;

type
  {$SCOPEDENUMS ON}
  TMonitorResultText = (Error, Warning, Note, ColumnLevel, ColumnFile, ColumnLine, ColumnRule, ColumnMessage,
    ColumnTarget, NoFindings, InvalidSarif, HtmlCount);
  {$SCOPEDENUMS OFF}

const
  cTexts: array[TMonitorResultText] of TAtlasText = (
    (De: 'Fehler'; En: 'Error'),
    (De: 'Warnung'; En: 'Warning'),
    (De: 'Hinweis'; En: 'Note'),
    (De: 'Schwere'; En: 'Severity'),
    (De: 'Datei'; En: 'File'),
    (De: 'Zeile'; En: 'Line'),
    (De: 'Regel'; En: 'Rule'),
    (De: 'Meldung'; En: 'Message'),
    (De: 'Ziel'; En: 'Target'),
    (De: 'Keine Befunde.'; En: 'No findings.'),
    (De: 'Die Ausgabe ist kein SARIF.'; En: 'The output is not SARIF.'),
    (De: '%d Befunde'; En: '%d findings'));

  cLevelError = 'error';
  cLevelWarning = 'warning';
  cLevelNote = 'note';
  cRankError = 3;
  cRankWarning = 2;
  cRankNote = 1;

{ Lesen }

/// <summary>Wurzeln aus originalUriBaseIds eines Laufs: Name → URI.</summary>
function BaseUri(ARun: TJSONObject; const AName: string): string;
var
  mBases: TJSONObject;
begin
  Result := '';
  mBases := TJsonRead.Obj(ARun, 'originalUriBaseIds');
  if AName <> '' then
  begin
    Result := TJsonRead.Text(TJsonRead.Obj(mBases, AName), 'uri');
  end;
end;

/// <summary>Dateipfad aus artifactLocation; relativ zu ihrer Wurzel aufgelöst.</summary>
function FileOf(ARun, ALocation: TJSONObject): string;
var
  mUri, mBase: string;
begin
  mUri := TJsonRead.Text(ALocation, 'uri');
  mBase := BaseUri(ARun, TJsonRead.Text(ALocation, 'uriBaseId'));
  if (mBase <> '') and not mUri.StartsWith('file:', True) then
  begin
    mUri := mBase + mUri;
  end;
  Result := TTextUris.ToPath(mUri);
  if Result = '' then
  begin
    // Relativer Pfad ohne Wurzel: wie geschrieben, mit Trennern des Systems.
    Result := TTextUris.NormalizePath(TTextUris.PercentDecode(mUri));
  end;
end;

/// <summary>Treffer aus der Baseline (unverändert oder nicht mehr gefunden) zeigt der Monitor nicht.</summary>
function FromBaseline(AResult: TJSONObject): Boolean;
var
  mState: string;
begin
  mState := TJsonRead.Text(AResult, 'baselineState');
  Result := (mState = 'unchanged') or (mState = 'absent') or (TJsonRead.Items(AResult, 'suppressions') <> nil);
end;

function FindingOf(ARun, AResult: TJSONObject; const ATarget: string): TMonitorFinding;
var
  mLocations: TJSONArray;
  mPhysical, mRegion: TJSONObject;
begin
  Result := Default(TMonitorFinding);
  Result.Target := ATarget;
  Result.RuleId := TJsonRead.Text(AResult, 'ruleId');
  Result.Level := TJsonRead.Text(AResult, 'level');
  if Result.Level = '' then
  begin
    Result.Level := cLevelWarning;
  end;
  // Die Meldung in der Sprache des Laufs steht unter properties.detail, message.text ist der Name der Regel.
  Result.Message := TJsonRead.Text(TJsonRead.Obj(AResult, 'properties'), 'detail');
  if Result.Message = '' then
  begin
    Result.Message := TJsonRead.Text(TJsonRead.Obj(AResult, 'message'), 'text');
  end;
  mLocations := TJsonRead.Items(AResult, 'locations');
  if (mLocations = nil) or (mLocations.Count = 0) then
  begin
    Exit;
  end;
  mPhysical := TJsonRead.Obj(TJsonRead.AsObject(mLocations.Items[0]), 'physicalLocation');
  Result.FileName := FileOf(ARun, TJsonRead.Obj(mPhysical, 'artifactLocation'));
  mRegion := TJsonRead.Obj(mPhysical, 'region');
  Result.Line := TJsonRead.IntOr(mRegion, 'startLine', 0);
  Result.Column := TJsonRead.IntOr(mRegion, 'startColumn', 0);
end;

/// <summary>Hängt die Befunde des Laufs ARun an AFindings an.</summary>
procedure AddRun(ARun: TJSONObject; const ATarget: string; var AFindings: TArray<TMonitorFinding>);
var
  mResults: TJSONArray;
  mValue: TJSONValue;
  mResult: TJSONObject;
begin
  mResults := TJsonRead.Items(ARun, 'results');
  if mResults = nil then
  begin
    Exit;
  end;
  for mValue in mResults do
  begin
    mResult := TJsonRead.AsObject(mValue);
    if (mResult <> nil) and not FromBaseline(mResult) then
    begin
      AFindings := AFindings + [FindingOf(ARun, mResult, ATarget)];
    end;
  end;
end;

class function TMonitorResults.ParseSarif(const AText, ATarget: string; out AFindings: TArray<TMonitorFinding>;
  out AError: string): Boolean;
var
  mRoot: TJSONObject;
  mRuns: TJSONArray;
  mValue: TJSONValue;
begin
  AFindings := nil;
  AError := '';
  mRoot := TJsonRead.ParseObject(AText);
  try
    mRuns := TJsonRead.Items(mRoot, 'runs');
    Result := mRuns <> nil;
    if not Result then
    begin
      AError := cTexts[TMonitorResultText.InvalidSarif].Text;
      Exit;
    end;
    for mValue in mRuns do
    begin
      if TJsonRead.AsObject(mValue) <> nil then
      begin
        AddRun(TJsonRead.AsObject(mValue), ATarget, AFindings);
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

{ Filtern }

/// <summary>Rang einer SARIF-Stufe: error 3, warning 2, note 1, sonst 0.</summary>
function LevelRank(const ALevel: string): Integer;
begin
  if ALevel = cLevelError then
  begin
    Result := cRankError;
  end
  else if ALevel = cLevelWarning then
  begin
    Result := cRankWarning;
  end
  else if ALevel = cLevelNote then
  begin
    Result := cRankNote;
  end
  else
  begin
    Result := 0;
  end;
end;

function Matches(const AFinding: TMonitorFinding; const AText: string): Boolean;
begin
  Result := (AText = '') or AFinding.FileName.ToLower.Contains(AText) or AFinding.RuleId.ToLower.Contains(AText) or
    AFinding.Message.ToLower.Contains(AText);
end;

class function TMonitorResults.Filter(const AFindings: TArray<TMonitorFinding>; const AText, ALevel: string):
  TArray<TMonitorFinding>;
var
  mFinding: TMonitorFinding;
  mText: string;
  mMinRank, mCount: Integer;
begin
  mText := Trim(AText).ToLower;
  mMinRank := LevelRank(ALevel);
  SetLength(Result, Length(AFindings));
  mCount := 0;
  for mFinding in AFindings do
  begin
    if (LevelRank(mFinding.Level) >= mMinRank) and Matches(mFinding, mText) then
    begin
      Result[mCount] := mFinding;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

{ Zusammenführen }

/// <summary>Hängt die Läufe ("runs") des SARIF-Texts AText an ARuns an.</summary>
procedure AppendRuns(ARuns: TJSONArray; const AText: string);
var
  mRoot: TJSONObject;
  mSource: TJSONArray;
  mValue: TJSONValue;
begin
  mRoot := TJsonRead.ParseObject(AText);
  try
    mSource := TJsonRead.Items(mRoot, 'runs');
    if mSource = nil then
    begin
      Exit;
    end;
    for mValue in mSource do
    begin
      ARuns.AddElement(mValue.Clone as TJSONValue);
    end;
  finally
    mRoot.Free;
  end;
end;

class function TMonitorResults.MergeSarif(const ATexts: TArray<string>): string;
var
  mMerged: TJSONObject;
  mRuns: TJSONArray;
  mText: string;
begin
  mMerged := TJSONObject.Create;
  try
    mMerged.AddPair('$schema', 'https://json.schemastore.org/sarif-2.1.0.json');
    mMerged.AddPair('version', '2.1.0');
    mRuns := TJSONArray.Create;
    mMerged.AddPair('runs', mRuns);
    for mText in ATexts do
    begin
      AppendRuns(mRuns, mText);
    end;
    Result := mMerged.ToJSON([]);
  finally
    mMerged.Free;
  end;
end;

{ HTML }

function Escape(const AText: string): string;
begin
  Result := AText.Replace('&', '&amp;', [rfReplaceAll]).Replace('<', '&lt;', [rfReplaceAll])
    .Replace('>', '&gt;', [rfReplaceAll]).Replace('"', '&quot;', [rfReplaceAll]);
end;

const
  cHtmlHead = '<!DOCTYPE html><html lang="%s"><head><meta charset="utf-8"><title>%s</title><style>' +
    'body{font-family:Segoe UI,sans-serif;margin:16px;color:#1f2328;background:#fff}' +
    'h1{font-size:20px}h2{font-size:16px;margin-top:24px}' +
    'table{border-collapse:collapse;width:100%%}th,td{border-bottom:1px solid #d0d7de;padding:4px 8px;' +
    'text-align:left;vertical-align:top}th{background:#f6f8fa}' +
    '.error{color:#cf222e}.warning{color:#9a6700}.note{color:#0969da}' +
    '@media (prefers-color-scheme:dark){body{color:#e6edf3;background:#0d1117}th{background:#161b22}' +
    'th,td{border-color:#30363d}}</style></head><body><h1>%s</h1><p>%s</p>';

procedure AppendTarget(ABuilder: TStringBuilder; const AFindings: TArray<TMonitorFinding>; const ATarget: string);
var
  mFinding: TMonitorFinding;
  mTitles: TArray<string>;
begin
  mTitles := TMonitorResults.ColumnTitles;
  ABuilder.Append('<h2>').Append(Escape(ATarget)).Append('</h2><table><tr>');
  ABuilder.Append(Format('<th>%s</th><th>%s</th><th>%s</th><th>%s</th><th>%s</th></tr>',
    [Escape(mTitles[0]), Escape(mTitles[1]), Escape(mTitles[2]), Escape(mTitles[3]), Escape(mTitles[4])]));
  for mFinding in AFindings do
  begin
    if mFinding.Target = ATarget then
    begin
      ABuilder.Append(Format('<tr><td class="%s">%s</td><td>%s</td><td>%d</td><td>%s</td><td>%s</td></tr>',
        [Escape(mFinding.Level), Escape(TMonitorResults.LevelText(mFinding.Level)), Escape(mFinding.FileName),
        mFinding.Line, Escape(mFinding.RuleId), Escape(mFinding.Message)]));
    end;
  end;
  ABuilder.Append('</table>');
end;

/// <summary>Ziele in der Reihenfolge ihres ersten Befunds.</summary>
function TargetsOf(const AFindings: TArray<TMonitorFinding>): TArray<string>;
var
  mFinding: TMonitorFinding;
  mTarget: string;
  mKnown: Boolean;
begin
  Result := nil;
  for mFinding in AFindings do
  begin
    mKnown := False;
    for mTarget in Result do
    begin
      mKnown := mKnown or (mTarget = mFinding.Target);
    end;
    if not mKnown then
    begin
      Result := Result + [mFinding.Target];
    end;
  end;
end;

class function TMonitorResults.Html(const AFindings: TArray<TMonitorFinding>; const ATitle: string): string;
var
  mBuilder: TStringBuilder;
  mTarget: string;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append(Format(cHtmlHead, [TAtlasLocale.Code(TAtlasLocale.Language), Escape(ATitle), Escape(ATitle),
      Escape(cTexts[TMonitorResultText.HtmlCount].Fmt([Length(AFindings)]))]));
    if AFindings = nil then
    begin
      mBuilder.Append('<p>').Append(Escape(cTexts[TMonitorResultText.NoFindings].Text)).Append('</p>');
    end;
    for mTarget in TargetsOf(AFindings) do
    begin
      AppendTarget(mBuilder, AFindings, mTarget);
    end;
    mBuilder.Append('</body></html>');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

{ Texte }

class function TMonitorResults.LevelText(const ALevel: string): string;
begin
  case LevelRank(ALevel) of
    cRankError:
      Result := cTexts[TMonitorResultText.Error].Text;
    cRankWarning:
      Result := cTexts[TMonitorResultText.Warning].Text;
  else
    Result := cTexts[TMonitorResultText.Note].Text;
  end;
end;

class function TMonitorResults.ColumnTitles: TArray<string>;
begin
  Result := TArray<string>.Create(cTexts[TMonitorResultText.ColumnLevel].Text,
    cTexts[TMonitorResultText.ColumnFile].Text, cTexts[TMonitorResultText.ColumnLine].Text,
    cTexts[TMonitorResultText.ColumnRule].Text, cTexts[TMonitorResultText.ColumnMessage].Text,
    cTexts[TMonitorResultText.ColumnTarget].Text);
end;

class function TMonitorResults.Columns(const AFinding: TMonitorFinding): TArray<string>;
begin
  Result := TArray<string>.Create(LevelText(AFinding.Level), AFinding.FileName, IntToStr(AFinding.Line),
    AFinding.RuleId, AFinding.Message, AFinding.Target);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Monitor.Results', cTexts);

end.
