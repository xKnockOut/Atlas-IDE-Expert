unit Atlas.Core.Assistants.HeldEdits;

// Zurückgehaltene Änderungen von KI-Assistenten an ungespeichert geänderten Dateien (#2605), ohne Windows und VCL.
// Statt eine solche Änderung abzulehnen, legt der Bearbeitungseingang sie hier ab (Datei, erwarteter Text, neuer
// Text, Client, Zeit) und antwortet dem MCP-Server sofort „wartet“. Der Mensch entscheidet in der IDE:
// - Speichern und übernehmen: Plan sagt, welcher Text danach im Puffer stehen soll. Steht dort noch der erwartete
//   Text, ist es der neue; sonst wird die Änderung über TAtlasLinePatch auf den aktuellen Stand übertragen, solange
//   sich die geänderten Bereiche nicht berühren. Berühren sie sich, bleibt nur der Vergleich.
// - Als Vergleich öffnen, Verwerfen: entfernt den Eintrag bzw. lässt ihn stehen.
// Mehrere Änderungen an derselben Datei werden nacheinander angeboten (NextFor: die älteste zuerst). Die Liste lebt
// nur im Speicher und geht mit dem Eingang (ADR 0017, Regel 3).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Assistants.EditChange,
  Atlas.Core.Assistants.Queue;

type
  TAtlasHeldEdit = record
    /// <summary>Kennung in der Liste, fortlaufend ab 1.</summary>
    Id: Integer;
    FileName: string;
    /// <summary>Text der Datei, von dem der KI-Assistent ausging (Platte beim Senden).</summary>
    Expected: string;
    /// <summary>Text, den der KI-Assistent schreiben wollte.</summary>
    Text: string;
    /// <summary>clientInfo.name des MCP-Clients; '' unbekannt.</summary>
    Client: string;
    /// <summary>Eingang (Ortszeit).</summary>
    Received: TDateTime;
    /// <summary>Geänderter Zeilenblock (Zeilen im neuen Text).</summary>
    function Change: TAtlasEditChange;
  end;

  TAtlasHeldEdits = class(TAtlasAssistantsQueue<TAtlasHeldEdit, Integer>)
  private
    FNextId: Integer;
  protected
    function KeyOf(const AItem: TAtlasHeldEdit): Integer; override;
  public
    /// <summary>Hält eine Änderung von AExpected nach AText an AFileName zurück; liefert ihre Kennung.</summary>
    function Add(const AFileName, AExpected, AText, AClient: string; AReceived: TDateTime): Integer;
    /// <summary>Wartende Änderungen an AFileName (ohne Groß-/Kleinschreibung).</summary>
    function CountFor(const AFileName: string): Integer;
    /// <summary>Älteste wartende Änderung überhaupt; False ohne.</summary>
    function TryFirst(out AEdit: TAtlasHeldEdit): Boolean;
    /// <summary>Älteste wartende Änderung an AFileName; False ohne.</summary>
    function TryNextFor(const AFileName: string; out AEdit: TAtlasHeldEdit): Boolean;
    procedure Clear;
    /// <summary>Alle wartenden Änderungen, älteste zuerst.</summary>
    function Items: TArray<TAtlasHeldEdit>;
    /// <summary>Text, der nach „Speichern und übernehmen“ im Puffer stehen soll, wenn dort ACurrent steht. False,
    /// wenn sich die Änderung mit dem überschneidet, was seit AEdit.Expected geändert wurde; dann bleibt nur der
    /// Vergleich.</summary>
    class function Plan(const AEdit: TAtlasHeldEdit; const ACurrent: string; out ANewText: string): Boolean;
      static;
  end;

implementation

uses
  Atlas.Core.Undo.LinePatch;

{ TAtlasHeldEdit }

function TAtlasHeldEdit.Change: TAtlasEditChange;
begin
  Result := TAtlasEditChange.Between(Expected, Text);
end;

{ TAtlasHeldEdits }

function TAtlasHeldEdits.KeyOf(const AItem: TAtlasHeldEdit): Integer;
begin
  Result := AItem.Id;
end;

function TAtlasHeldEdits.Add(const AFileName, AExpected, AText, AClient: string; AReceived: TDateTime): Integer;
var
  mEdit: TAtlasHeldEdit;
begin
  Inc(FNextId);
  mEdit := Default(TAtlasHeldEdit);
  mEdit.Id := FNextId;
  mEdit.FileName := AFileName;
  mEdit.Expected := AExpected;
  mEdit.Text := AText;
  mEdit.Client := AClient;
  mEdit.Received := AReceived;
  FItems.Add(mEdit);
  Result := mEdit.Id;
end;

function TAtlasHeldEdits.CountFor(const AFileName: string): Integer;
var
  mEdit: TAtlasHeldEdit;
begin
  Result := 0;
  for mEdit in FItems do
  begin
    if SameText(mEdit.FileName, AFileName) then
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasHeldEdits.TryFirst(out AEdit: TAtlasHeldEdit): Boolean;
begin
  AEdit := Default(TAtlasHeldEdit);
  Result := FItems.Count > 0;
  if Result then
  begin
    AEdit := FItems[0];
  end;
end;

function TAtlasHeldEdits.TryNextFor(const AFileName: string; out AEdit: TAtlasHeldEdit): Boolean;
var
  mEdit: TAtlasHeldEdit;
begin
  AEdit := Default(TAtlasHeldEdit);
  for mEdit in FItems do
  begin
    if SameText(mEdit.FileName, AFileName) then
    begin
      AEdit := mEdit;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAtlasHeldEdits.Clear;
begin
  FItems.Clear;
end;

function TAtlasHeldEdits.Items: TArray<TAtlasHeldEdit>;
begin
  Result := FItems.ToArray;
end;

class function TAtlasHeldEdits.Plan(const AEdit: TAtlasHeldEdit; const ACurrent: string;
  out ANewText: string): Boolean;
begin
  if ACurrent = AEdit.Expected then
  begin
    ANewText := AEdit.Text;
    Exit(True);
  end;
  Result := TAtlasLinePatch.Rebase(AEdit.Expected, AEdit.Text, ACurrent, ANewText);
end;

end.
