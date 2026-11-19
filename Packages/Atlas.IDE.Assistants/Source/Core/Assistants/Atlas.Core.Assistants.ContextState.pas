unit Atlas.Core.Assistants.ContextState;

// Zustand der IDE für KI-Assistenten (#2050) ohne Open Tools API: Wann das Modul schreibt (TAtlasContextPace) und
// wie Auswahl und letzter Build in das Format von Atlas.Text.IdeContext kommen. Geschrieben wird erst, wenn ein
// neuer Stand (TIdeContexts.ChangeKey) cQuietMs lang gleich bleibt; Tippen in derselben Methode ändert den
// Schlüssel nicht und schreibt deshalb nicht.

interface

uses
  Atlas.Text.IdeContext,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Verdict;

type
  TAtlasContextPace = record
  public const
    /// <summary>So lange muss ein neuer Stand ruhen, bevor er geschrieben wird.</summary>
    cQuietMs = 500;
  private
    FWritten: string;
    FPending: string;
    FPendingSince: UInt64;
    FHasWritten: Boolean;
  public
    /// <summary>Stand AKey zum Zeitpunkt ANowMs (fortlaufende Millisekunden); True = jetzt schreiben.</summary>
    function Due(const AKey: string; ANowMs: UInt64): Boolean;
    /// <summary>Nächster Stand wird geschrieben, auch wenn er gleich ist (z. B. nach dem Einschalten).</summary>
    procedure Forget;
  end;

  TAtlasAssistantContext = class
  public
    /// <summary>Bereich einer Auswahl von AStartLine:AStartColumn bis AEndLine:AEndColumn (ab 1), noch ohne Text.
    /// </summary>
    class function Range(AStartLine, AStartColumn, AEndLine, AEndColumn: Integer): TIdeContextSelection; static;
    /// <summary>Auswahl im Bereich ARange mit AText; ohne AWithText nur der Bereich, sonst gekürzt auf AMax Zeichen.
    /// </summary>
    class function Selection(const ARange: TIdeContextSelection; const AText: string; AWithText: Boolean;
      AMax: Integer): TIdeContextSelection; static;
    /// <summary>Letzter Build für die Datei: Art, Zahlen aus AVerdict (nach Basislinie), maßgebliche Meldungen.
    /// </summary>
    class function Build(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict; AFinishedAtUtc: TDateTime): TIdeContextBuild; static;
    class function KindText(AKind: TAtlasCompileKind): string; static;
    class function SeverityText(ASeverity: TAtlasCompilerSeverity): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasContextPace }

function TAtlasContextPace.Due(const AKey: string; ANowMs: UInt64): Boolean;
begin
  Result := False;
  if FHasWritten and (AKey = FWritten) then
  begin
    // Zurück zum geschriebenen Stand: nichts vormerken.
    FPending := FWritten;
    Exit;
  end;
  if AKey <> FPending then
  begin
    FPending := AKey;
    FPendingSince := ANowMs;
    Exit;
  end;
  Result := ANowMs - FPendingSince >= cQuietMs;
  if Result then
  begin
    FWritten := AKey;
    FHasWritten := True;
  end;
end;

procedure TAtlasContextPace.Forget;
begin
  FHasWritten := False;
  FWritten := '';
end;

{ TAtlasAssistantContext }

class function TAtlasAssistantContext.Range(AStartLine, AStartColumn, AEndLine, AEndColumn: Integer):
  TIdeContextSelection;
begin
  Result := Default(TIdeContextSelection);
  Result.StartLine := AStartLine;
  Result.StartColumn := AStartColumn;
  Result.EndLine := AEndLine;
  Result.EndColumn := AEndColumn;
end;

class function TAtlasAssistantContext.Selection(const ARange: TIdeContextSelection; const AText: string;
  AWithText: Boolean; AMax: Integer): TIdeContextSelection;
begin
  Result := Range(ARange.StartLine, ARange.StartColumn, ARange.EndLine, ARange.EndColumn);
  Result.Known := True;
  Result.Length := Length(AText);
  Result.TextOmitted := not AWithText;
  if AWithText then
  begin
    Result.Text := TIdeContexts.Shorten(AText, AMax, Result.Truncated);
  end;
end;

class function TAtlasAssistantContext.KindText(AKind: TAtlasCompileKind): string;
const
  cNames: array[TAtlasCompileKind] of string = ('make', 'build', 'check', 'makeUnit', 'clean', 'link');
begin
  Result := cNames[AKind];
end;

class function TAtlasAssistantContext.SeverityText(ASeverity: TAtlasCompilerSeverity): string;
const
  cNames: array[TAtlasCompilerSeverity] of string = ('info', 'hint', 'warning', 'error', 'fatal');
begin
  Result := cNames[ASeverity];
end;

class function TAtlasAssistantContext.Build(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; const AVerdict: TAtlasBuildVerdict;
  AFinishedAtUtc: TDateTime): TIdeContextBuild;
var
  mMessage: TAtlasCompilerMessage;
  mItem: TIdeContextMessage;
  mItems: TArray<TIdeContextMessage>;
begin
  Result := Default(TIdeContextBuild);
  Result.Known := True;
  Result.Project := AProject.FileName;
  Result.Kind := KindText(AProject.Kind);
  Result.Success := AVerdict.Effective;
  Result.Errors := AVerdict.Errors;
  Result.Warnings := AVerdict.Warnings;
  Result.Hints := AVerdict.Hints;
  Result.FinishedAtUtc := AFinishedAtUtc;
  mItems := nil;
  for mMessage in AMessages do
  begin
    mItem := Default(TIdeContextMessage);
    mItem.FileName := mMessage.FileName;
    mItem.Line := mMessage.Line;
    mItem.Column := mMessage.Column;
    mItem.Severity := SeverityText(mMessage.Severity);
    mItem.Code := mMessage.Code;
    mItem.Text := mMessage.Text;
    mItems := mItems + [mItem];
  end;
  Result.Messages := TIdeContexts.Relevant(mItems);
end;

end.
