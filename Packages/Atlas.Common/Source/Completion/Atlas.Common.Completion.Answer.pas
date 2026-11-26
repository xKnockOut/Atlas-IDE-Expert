unit Atlas.Common.Completion.Answer;

// Antwort der Vervollständigung im Aufbau und die Quellen, die andere Features anmelden: Eine Quelle
// (TCompletionSource) bekommt Anfrage und Antwort und läuft an ihrer Stelle (TCompletionSlot) in der festen
// Reihenfolge des Sprachservers. Die Quellen meldet die Komposition vor der ersten Anfrage an
// (TCompletionSources.Add); danach wird nur noch gelesen.

interface

uses
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Completion.Request,
  Atlas.Common.Completion.Contract;

type
  /// <summary>Antwort im Aufbau: Hinweise oben, vorab bestimmte Einträge (Aufzählungswerte, Komponenten; bei
  /// Staffelung schon gesendet), die allgemeine Liste und der Schluss (Code-Vorlagen, Deklarieren). Ein
  /// exklusiver Fall antwortet mit Exclusive allein.</summary>
  TCompletionAnswer = class
  public
    Hints: TArray<TCompletionItem>;
    Prefetched: TArray<TCompletionItem>;
    Body: TArray<TCompletionItem>;
    Tail: TArray<TCompletionItem>;
    Incomplete: Boolean;
    /// <summary>Passende Mitglieder, die nur wegen der Sichtbarkeit fehlen (#2108).</summary>
    Hidden: TArray<TCompletionHiddenMember>;
    Exclusive: TCompletionItems;
    /// <summary>partialResultToken (#616); '' ohne Staffelung.</summary>
    Token: string;
    /// <summary>Schon als $/progress gesendete Einträge; die Antwort setzt sortText dahinter fort.</summary>
    SentCount: Integer;
    Partial: TCompletionPartialProc;
    Cancellation: IJsonRpcCancellationToken;
    /// <summary>Antwortet mit AItem allein.</summary>
    function AnswerWith(const AItem: TCompletionItem): TCompletionOutcome;
  end;

  /// <summary>Eine angemeldete Quelle der Vervollständigung.</summary>
  TCompletionSource = reference to function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer):
    TCompletionOutcome;

  /// <summary>Angemeldete Quellen je Stelle, in der Reihenfolge der Anmeldung.</summary>
  TCompletionSources = class
  private
    FSources: array[TCompletionSlot] of TArray<TCompletionSource>;
  public
    /// <summary>Meldet ASource an ASlot an; nur vor der ersten Anfrage.</summary>
    procedure Add(ASlot: TCompletionSlot; const ASource: TCompletionSource);
    /// <summary>Lässt die Quellen an ASlot der Reihe nach laufen, bis eine antwortet.</summary>
    function Run(ASlot: TCompletionSlot; ARequest: TCompletionRequest; AAnswer: TCompletionAnswer):
      TCompletionOutcome;
  end;

implementation

{ TCompletionAnswer }

function TCompletionAnswer.AnswerWith(const AItem: TCompletionItem): TCompletionOutcome;
begin
  Exclusive := Default(TCompletionItems);
  Exclusive.Items := [AItem];
  Result := TCompletionOutcome.Answered;
end;

{ TCompletionSources }

procedure TCompletionSources.Add(ASlot: TCompletionSlot; const ASource: TCompletionSource);
begin
  SetLength(FSources[ASlot], Length(FSources[ASlot]) + 1);
  FSources[ASlot][High(FSources[ASlot])] := ASource;
end;

function TCompletionSources.Run(ASlot: TCompletionSlot; ARequest: TCompletionRequest;
  AAnswer: TCompletionAnswer): TCompletionOutcome;
var
  mSource: TCompletionSource;
begin
  Result := TCompletionOutcome.Next;
  for mSource in FSources[ASlot] do
  begin
    Result := mSource(ARequest, AAnswer);
    if Result = TCompletionOutcome.Answered then
    begin
      Exit;
    end;
  end;
end;

end.
