unit Editing.Completion.ContextSnippets;

// Quelle der Vervollständigung für kontextabhängige Code-Vorlagen am Zeilenanfang (#51): prop, changed, create,
// free aus Editing.ContextSnippets, passend zum getippten Wort. Mit Snippet-Unterstützung des Clients
// als LSP-Snippet, sonst als Klartext ohne Platzhalter. Läuft an TCompletionSlot.ContextSnippets und hängt die
// Einträge ans Ende der Liste.

interface

uses
  Atlas.Common.Completion.Contract,
  Atlas.Common.Completion.Request,
  Atlas.Common.Completion.Answer;

type
  TEditingContextSnippetCompletion = class
  public
    /// <summary>Code-Vorlagen für die Zeile der Position von ARequest.</summary>
    class function Items(ARequest: TCompletionRequest): TArray<TCompletionItem>; static;
    /// <summary>Quelle für TCompletionSlot.ContextSnippets.</summary>
    class function Source: TCompletionSource; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Completion.FuzzyMatch,
  Editing.Contract,
  Editing.ContextSnippets;

/// <summary>Getipptes Wort vor dem Cursor in ALineText; AStart ist die Spalte davor.</summary>
function WordBefore(const ALineText: string; ACharacter: Integer; out AStart: Integer): string;
begin
  AStart := Min(ACharacter, Length(ALineText));
  while (AStart > 0) and CharInSet(ALineText[AStart], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
  begin
    Dec(AStart);
  end;
  Result := Copy(ALineText, AStart + 1, ACharacter - AStart);
end;

/// <summary>Eintrag für ASnippet; ersetzt ab AStart bis zum Cursor.</summary>
function SnippetItem(ARequest: TCompletionRequest; const ASnippet: TContextSnippet; AStart: Integer;
  ASnippetSupport: Boolean): TCompletionItem;
var
  mText: string;
begin
  Result := Default(TCompletionItem);
  Result.Name := ASnippet.Name;
  Result.Detail := ASnippet.Description;
  Result.Kind := cKindSnippet;
  Result.FilterText := ASnippet.Prefix;
  Result.HasTextEdit := True;
  Result.Snippet := ASnippetSupport;
  mText := ASnippet.Text;
  if not ASnippetSupport then
  begin
    mText := TContextSnippets.ToPlain(mText);
  end;
  Result.TextEdit := TTextEdit.Create(TTextRange.Create(ARequest.Position.Line, AStart, ARequest.Position.Line,
    ARequest.Position.Character), mText);
  Result.AdditionalEdits := ASnippet.AdditionalEdits;
  // Atlas wertet die weiteren Änderungen dann nicht als uses-Ergänzung.
  Result.Action := 'snippet';
end;

{ TEditingContextSnippetCompletion }

class function TEditingContextSnippetCompletion.Items(ARequest: TCompletionRequest): TArray<TCompletionItem>;
var
  mSlash: TSlashContext;
  mSnippet: TContextSnippet;
  mLineText, mWord: string;
  mStart: Integer;
begin
  Result := nil;
  mLineText := ARequest.LineText(ARequest.Position.Line);
  // TContextSnippets prüft, dass sonst nichts in der Zeile steht.
  mWord := WordBefore(mLineText, ARequest.Position.Character, mStart);
  mSlash := Default(TSlashContext);
  mSlash.Text := ARequest.Text;
  mSlash.Line := ARequest.Position.Line;
  mSlash.LineText := mLineText;
  mSlash.Index := ARequest.Index;
  mSlash.Namespaces := ARequest.Namespaces;
  for mSnippet in TContextSnippets.At(mSlash, ARequest.Position.Character) do
  begin
    if (MatchScore(mSnippet.Prefix, mWord, ARequest.Matching) <> TFuzzyMatch.cNoMatch) or
      (MatchScore(mSnippet.Name, mWord, ARequest.Matching) <> TFuzzyMatch.cNoMatch) then
    begin
      Result := Result + [SnippetItem(ARequest, mSnippet, mStart, ARequest.SnippetSupport)];
    end;
  end;
end;

class function TEditingContextSnippetCompletion.Source: TCompletionSource;
begin
  Result :=
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    begin
      AAnswer.Tail := AAnswer.Tail + Items(ARequest);
      Result := TCompletionOutcome.Next;
    end;
end;

end.
