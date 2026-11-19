unit Atlas.Common.Mcp.IdeContext;

// Zustand der IDE für KI-Assistenten (MCP-Werkzeug get_ide_context, #2050): wo der Entwickler gerade ist (Datei,
// Cursor, Methode, Auswahl, aktives Projekt, letzter Build, Reiter). Das Plugin schreibt ihn je IDE nach
// ide-context-<pid>.json (Atlas.Text.IdeContext). Laufen mehrere IDEs, gilt die mit dem jüngsten Stand oder die
// per ide gewählte. Die Dateien liest die Shell; hier nur Auswahl und Ausgabe (Text oder JSON), damit es ohne
// Dateisystem testbar bleibt. Lesen und Prüfen des Codes bleibt bei den übrigen Werkzeugen.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.IdeContext;

type
{$SCOPEDENUMS ON}
  TMcpIdeContextPart = (Editor, Selection, Project, Build, Tabs);
{$SCOPEDENUMS OFF}
  TMcpIdeContextParts = set of TMcpIdeContextPart;

  TMcpIdeContextRequest = record
    Parts: TMcpIdeContextParts;
    /// <summary>Prozess der IDE; 0 = die mit dem jüngsten Stand.</summary>
    Ide: Cardinal;
    AsJson: Boolean;
    /// <summary>Argumente von get_ide_context; EMcpToolError bei ungültigen Werten.</summary>
    class function FromArguments(const AArguments: TJSONObject): TMcpIdeContextRequest; static;
  end;

  TMcpIdeContext = class
  public const
    /// <summary>So viele Zeilen der Auswahl zeigt die Textausgabe.</summary>
    cSelectionLines = 30;
    /// <summary>So viele Meldungen des Builds zeigt die Textausgabe.</summary>
    cBuildMessages = 10;
  public
    /// <summary>Index des Stands zu AIde bzw. des jüngsten (AIde = 0); -1 mit Grund in AReason.</summary>
    class function Pick(const AContexts: TArray<TIdeContext>; AIde: Cardinal; out AReason: string): Integer; static;
    /// <summary>Ergebnis von get_ide_context; ANowUtc für das Alter des Stands.</summary>
    class function Report(const AContext: TIdeContext; const ARequest: TMcpIdeContextRequest;
      ANowUtc: TDateTime): string; static;
    /// <summary>Antwort ohne Stand: ARunning sind die laufenden IDEs mit Atlas-Plugin (aus editor-dirty).</summary>
    class function NoContext(const ARunning: TArray<Cardinal>): string; static;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.DateUtils,
  Atlas.Text.Json,
  Atlas.Text.Lines,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  TIdeContextText = (NoIde, NotProvided, UnknownIde, IncludeInvalid, IdeInvalid, FormatInvalid, Header, Seconds,
    Minutes, Hours, Editor, Unsaved, Method, Selection, SelectionNoText, Truncated, MoreLines, Project, Group,
    Build, BuildCounts, Succeeded, Failed, Tabs, NoEditor, NoBuild);

const
  cTexts: array[TIdeContextText] of TAtlasText = (
    (De: 'Keine IDE mit Atlas-Plugin gefunden.'; En: 'No IDE with the Atlas plugin found.'),
    (De: 'Die IDE (Prozess %s) stellt ihren Zustand nicht bereit: Das Modul KI-Assistenten fehlt oder ' +
      'assistants.context ist aus.';
     En: 'The IDE (process %s) does not provide its state: the AI assistants module is missing or ' +
      'assistants.context is off.'),
    (De: 'Keine IDE mit Prozess %d. Laufende IDEs mit Zustand: %s'; En: 'No IDE with process %d. Running IDEs ' +
      'with state: %s'),
    (De: '"include" ist eine Liste aus editor, selection, project, build und tabs';
     En: '"include" is a list of editor, selection, project, build and tabs'),
    (De: '"ide" ist eine Prozessnummer größer 0'; En: '"ide" is a process number greater than 0'),
    (De: '"format" ist text oder json'; En: '"format" is text or json'),
    (De: 'IDE %d · Stand %s (%s)'; En: 'IDE %d · state %s (%s)'),
    (De: 'vor %d s'; En: '%d s ago'),
    (De: 'vor %d Min.'; En: '%d min ago'),
    (De: 'vor %d Std.'; En: '%d h ago'),
    (De: 'Editor     %s:%d:%d'; En: 'Editor     %s:%d:%d'),
    (De: '  (ungespeichert)'; En: '  (unsaved)'),
    (De: 'Methode    %s'; En: 'Method     %s'),
    (De: 'Auswahl    Z. %d:%d–%d:%d (%d Zeichen)'; En: 'Selection  l. %d:%d–%d:%d (%d characters)'),
    (De: '           (Text abgeschaltet: assistants.context.selection)';
     En: '           (text switched off: assistants.context.selection)'),
    (De: '           … gekürzt auf %d Zeichen'; En: '           … shortened to %d characters'),
    (De: '           … %d weitere Zeilen'; En: '           … %d more lines'),
    (De: 'Projekt    %s'; En: 'Project    %s'),
    (De: 'Gruppe     %s'; En: 'Group      %s'),
    (De: 'Build      %s · %s · %s'; En: 'Build      %s · %s · %s'),
    (De: '%d Fehler, %d Warnungen, %d Hinweise'; En: '%d errors, %d warnings, %d hints'),
    (De: 'erfolgreich'; En: 'succeeded'),
    (De: 'fehlgeschlagen'; En: 'failed'),
    (De: 'Reiter     %s'; En: 'Tabs       %s'),
    (De: 'Editor     (keine Datei offen)'; En: 'Editor     (no file open)'),
    (De: 'Build      (noch keiner in dieser Sitzung)'; En: 'Build      (none in this session yet)'));

  cPartNames: array[TMcpIdeContextPart] of string = ('editor', 'selection', 'project', 'build', 'tabs');
  cAllParts = [TMcpIdeContextPart.Editor, TMcpIdeContextPart.Selection, TMcpIdeContextPart.Project,
    TMcpIdeContextPart.Build, TMcpIdeContextPart.Tabs];

{$SCOPEDENUMS OFF}

function PartOf(const AName: string; out APart: TMcpIdeContextPart): Boolean;
var
  mPart: TMcpIdeContextPart;
begin
  for mPart := Low(TMcpIdeContextPart) to High(TMcpIdeContextPart) do
  begin
    if SameText(AName, cPartNames[mPart]) then
    begin
      APart := mPart;
      Exit(True);
    end;
  end;
  Result := False;
end;

function PartsOf(AValue: TJSONValue): TMcpIdeContextParts;
var
  mItem: TJSONValue;
  mPart: TMcpIdeContextPart;
begin
  if AValue = nil then
  begin
    Exit(cAllParts);
  end;
  if not (AValue is TJSONArray) then
  begin
    raise EMcpToolError.Create(cTexts[TIdeContextText.IncludeInvalid].Text);
  end;
  Result := [];
  for mItem in TJSONArray(AValue) do
  begin
    if not TJsonRead.IsString(mItem) or not PartOf(mItem.Value, mPart) then
    begin
      raise EMcpToolError.Create(cTexts[TIdeContextText.IncludeInvalid].Text);
    end;
    Include(Result, mPart);
  end;
  if Result = [] then
  begin
    Result := cAllParts;
  end;
end;

{ TMcpIdeContextRequest }

class function TMcpIdeContextRequest.FromArguments(const AArguments: TJSONObject): TMcpIdeContextRequest;
var
  mFormat: string;
  mIde: Int64;
begin
  Result := Default(TMcpIdeContextRequest);
  Result.Parts := PartsOf(TJsonRead.Value(AArguments, 'include'));
  if TJsonRead.TryInt64(AArguments, 'ide', mIde) then
  begin
    if (mIde <= 0) or (mIde > High(Cardinal)) then
    begin
      raise EMcpToolError.Create(cTexts[TIdeContextText.IdeInvalid].Text);
    end;
    Result.Ide := Cardinal(mIde);
  end;
  mFormat := Trim(TMcpArgs.OptionalString(AArguments, 'format'));
  if (mFormat <> '') and not SameText(mFormat, 'text') and not SameText(mFormat, 'json') then
  begin
    raise EMcpToolError.Create(cTexts[TIdeContextText.FormatInvalid].Text);
  end;
  Result.AsJson := SameText(mFormat, 'json');
end;

{ Text }

function AgeText(AAtUtc, ANowUtc: TDateTime): string;
var
  mSeconds: Int64;
begin
  mSeconds := SecondsBetween(ANowUtc, AAtUtc);
  if mSeconds < 120 then
  begin
    Exit(cTexts[TIdeContextText.Seconds].Fmt([mSeconds]));
  end;
  if mSeconds < 2 * 3600 then
  begin
    Exit(cTexts[TIdeContextText.Minutes].Fmt([mSeconds div 60]));
  end;
  Result := cTexts[TIdeContextText.Hours].Fmt([mSeconds div 3600]);
end;

function LocalText(ALocal: TDateTime): string;
begin
  Result := FormatDateTime('dd"."mm"."yyyy hh":"nn":"ss', ALocal, TFormatSettings.Invariant);
end;

procedure AddLine(var AText: string; const ALine: string);
begin
  AText := AText + ALine + sLineBreak;
end;

procedure AddEditor(var AText: string; const AEditor: TIdeContextEditor);
var
  mLine: string;
begin
  if not AEditor.Known then
  begin
    AddLine(AText, cTexts[TIdeContextText.NoEditor].Text);
    Exit;
  end;
  mLine := cTexts[TIdeContextText.Editor].Fmt([AEditor.FileName, AEditor.Line, AEditor.Column]);
  if AEditor.Modified then
  begin
    mLine := mLine + cTexts[TIdeContextText.Unsaved].Text;
  end;
  AddLine(AText, mLine);
  if AEditor.Method <> '' then
  begin
    AddLine(AText, cTexts[TIdeContextText.Method].Fmt([AEditor.Method]));
  end;
end;

procedure AddSelection(var AText: string; const ASelection: TIdeContextSelection);
var
  mLines: TArray<string>;
  mIndex: Integer;
begin
  if not ASelection.Known then
  begin
    Exit;
  end;
  AddLine(AText, cTexts[TIdeContextText.Selection].Fmt([ASelection.StartLine, ASelection.StartColumn,
    ASelection.EndLine, ASelection.EndColumn, ASelection.Length]));
  if ASelection.TextOmitted then
  begin
    AddLine(AText, cTexts[TIdeContextText.SelectionNoText].Text);
    Exit;
  end;
  mLines := TTextLines.SplitLines(ASelection.Text);
  for mIndex := 0 to High(mLines) do
  begin
    if mIndex >= TMcpIdeContext.cSelectionLines then
    begin
      AddLine(AText, cTexts[TIdeContextText.MoreLines].Fmt([Length(mLines) - mIndex]));
      Break;
    end;
    AddLine(AText, '           ' + mLines[mIndex]);
  end;
  if ASelection.Truncated then
  begin
    AddLine(AText, cTexts[TIdeContextText.Truncated].Fmt([Length(ASelection.Text)]));
  end;
end;

procedure AddProject(var AText: string; const AProject: TIdeContextProject);
var
  mLine: string;
begin
  if AProject.FileName = '' then
  begin
    Exit;
  end;
  mLine := AProject.FileName;
  if AProject.Configuration <> '' then
  begin
    mLine := mLine + ' · ' + AProject.Configuration;
  end;
  if AProject.Platform <> '' then
  begin
    mLine := mLine + ' · ' + AProject.Platform;
  end;
  AddLine(AText, cTexts[TIdeContextText.Project].Fmt([mLine]));
  if AProject.Group <> '' then
  begin
    AddLine(AText, cTexts[TIdeContextText.Group].Fmt([AProject.Group]));
  end;
end;

function MessageText(const AMessage: TIdeContextMessage): string;
begin
  Result := '           ';
  if AMessage.Code <> '' then
  begin
    Result := Result + AMessage.Code + ' ';
  end;
  if AMessage.FileName <> '' then
  begin
    Result := Result + Format('%s:%d  ', [ExtractFileName(AMessage.FileName.Replace('\', PathDelim)),
      AMessage.Line]);
  end;
  Result := Result + AMessage.Text;
end;

procedure AddBuild(var AText: string; const ABuild: TIdeContextBuild; ANowUtc: TDateTime);
var
  mIndex: Integer;
  mResult: string;
begin
  if not ABuild.Known then
  begin
    AddLine(AText, cTexts[TIdeContextText.NoBuild].Text);
    Exit;
  end;
  mResult := cTexts[TIdeContextText.Failed].Text;
  if ABuild.Success then
  begin
    mResult := cTexts[TIdeContextText.Succeeded].Text;
  end;
  AddLine(AText, cTexts[TIdeContextText.Build].Fmt([AgeText(ABuild.FinishedAtUtc, ANowUtc), ABuild.Kind,
    cTexts[TIdeContextText.BuildCounts].Fmt([ABuild.Errors, ABuild.Warnings, ABuild.Hints]) + ' · ' + mResult]));
  for mIndex := 0 to High(ABuild.Messages) do
  begin
    if mIndex >= TMcpIdeContext.cBuildMessages then
    begin
      AddLine(AText, cTexts[TIdeContextText.MoreLines].Fmt([Length(ABuild.Messages) - mIndex]));
      Break;
    end;
    AddLine(AText, MessageText(ABuild.Messages[mIndex]));
  end;
end;

procedure AddTabs(var AText: string; const ATabs: TArray<string>);
var
  mNames: TArray<string>;
  mTab: string;
begin
  mNames := nil;
  for mTab in ATabs do
  begin
    mNames := mNames + [ExtractFileName(mTab.Replace('\', PathDelim))];
  end;
  if Length(mNames) > 0 then
  begin
    AddLine(AText, cTexts[TIdeContextText.Tabs].Fmt([string.Join(', ', mNames)]));
  end;
end;

function TextReport(const AContext: TIdeContext; const AParts: TMcpIdeContextParts; ANowUtc: TDateTime): string;
begin
  Result := '';
  AddLine(Result, cTexts[TIdeContextText.Header].Fmt([AContext.Pid, AgeText(AContext.AtUtc, ANowUtc),
    LocalText(AContext.AtLocal)]));
  if TMcpIdeContextPart.Editor in AParts then
  begin
    AddEditor(Result, AContext.Editor);
  end;
  if TMcpIdeContextPart.Selection in AParts then
  begin
    AddSelection(Result, AContext.Selection);
  end;
  if TMcpIdeContextPart.Project in AParts then
  begin
    AddProject(Result, AContext.Project);
  end;
  if TMcpIdeContextPart.Build in AParts then
  begin
    AddBuild(Result, AContext.Build, ANowUtc);
  end;
  if TMcpIdeContextPart.Tabs in AParts then
  begin
    AddTabs(Result, AContext.Tabs);
  end;
  Result := TrimRight(Result);
end;

/// <summary>Inhalt der Datei mit den Abschnitten aus AParts und dem Alter in Sekunden.</summary>
function JsonReport(const AContext: TIdeContext; const AParts: TMcpIdeContextParts; ANowUtc: TDateTime): string;
var
  mRoot: TJSONObject;
  mPart: TMcpIdeContextPart;
begin
  mRoot := TJsonRead.ParseObject(TIdeContexts.ToJson(AContext));
  try
    mRoot.RemovePair('format').Free;
    for mPart := Low(TMcpIdeContextPart) to High(TMcpIdeContextPart) do
    begin
      if not (mPart in AParts) then
      begin
        mRoot.RemovePair(cPartNames[mPart]).Free;
      end;
    end;
    mRoot.AddPair('ageSeconds', TJSONNumber.Create(SecondsBetween(ANowUtc, AContext.AtUtc)));
    Result := mRoot.Format(2);
  finally
    mRoot.Free;
  end;
end;

function PidList(const AContexts: TArray<TIdeContext>): string;
var
  mContext: TIdeContext;
begin
  Result := '';
  for mContext in AContexts do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + UIntToStr(mContext.Pid);
  end;
end;

{ TMcpIdeContext }

class function TMcpIdeContext.Pick(const AContexts: TArray<TIdeContext>; AIde: Cardinal;
  out AReason: string): Integer;
var
  mIndex: Integer;
begin
  AReason := '';
  Result := -1;
  for mIndex := 0 to High(AContexts) do
  begin
    if AIde <> 0 then
    begin
      if AContexts[mIndex].Pid = AIde then
      begin
        Exit(mIndex);
      end;
    end
    else if (Result < 0) or (AContexts[mIndex].AtUtc > AContexts[Result].AtUtc) then
    begin
      Result := mIndex;
    end;
  end;
  if Result < 0 then
  begin
    AReason := cTexts[TIdeContextText.UnknownIde].Fmt([AIde, PidList(AContexts)]);
  end;
end;

class function TMcpIdeContext.Report(const AContext: TIdeContext; const ARequest: TMcpIdeContextRequest;
  ANowUtc: TDateTime): string;
begin
  if ARequest.AsJson then
  begin
    Result := JsonReport(AContext, ARequest.Parts, ANowUtc);
  end
  else
  begin
    Result := TextReport(AContext, ARequest.Parts, ANowUtc);
  end;
end;

class function TMcpIdeContext.NoContext(const ARunning: TArray<Cardinal>): string;
var
  mPids: string;
  mPid: Cardinal;
begin
  if Length(ARunning) = 0 then
  begin
    Exit(cTexts[TIdeContextText.NoIde].Text);
  end;
  mPids := '';
  for mPid in ARunning do
  begin
    if mPids <> '' then
    begin
      mPids := mPids + ', ';
    end;
    mPids := mPids + UIntToStr(mPid);
  end;
  Result := cTexts[TIdeContextText.NotProvided].Fmt([mPids]);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.IdeContext', cTexts);

end.
