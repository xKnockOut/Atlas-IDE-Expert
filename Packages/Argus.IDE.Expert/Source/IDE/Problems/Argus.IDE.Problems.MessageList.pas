unit Argus.IDE.Problems.MessageList;

// Liste der Probleme im Meldungsfenster (#398): eigene Gruppe „Argus-Probleme“,
// je Problem eine Zeile mit Datei, Zeile und Spalte (Doppelklick springt hin).
// Compilermeldungen stehen schon im Reiter „Build“ und fehlen hier. Neu
// aufgebaut wird nur, wenn sich der Inhalt geändert hat; höchstens MaxEntries
// Zeilen. Die Gruppe wird nicht nach vorn geholt.

interface

uses
  System.SysUtils,
  Argus.Core.Problems.Contract,
  Argus.Core.Problems.Store;

type
  TArgusProblemsList = class
  public const
    MaxEntries = 1000;
  private
    FSignature: string;
  public
    /// <summary>Gruppe nach AStore aufbauen, falls sich etwas geändert hat.</summary>
    procedure Update(AStore: TArgusProblemStore);
    /// <summary>Gruppe leeren.</summary>
    procedure Clear;
  end;

implementation

uses
  ToolsAPI,
  Argus.UI.Strings;

function SeverityText(ASeverity: TArgusProblemSeverity): string;
begin
  case ASeverity of
    TArgusProblemSeverity.Error:
      Result := TArgusStrings.Text(TArgusTextId.SeverityError);
    TArgusProblemSeverity.Warning:
      Result := TArgusStrings.Text(TArgusTextId.SeverityWarning);
    TArgusProblemSeverity.Information:
      Result := TArgusStrings.Text(TArgusTextId.SeverityInformation);
  else
    Result := TArgusStrings.Text(TArgusTextId.SeverityHint);
  end;
end;

function Group(const AMessages: IOTAMessageServices; ACreate: Boolean): IOTAMessageGroup;
var
  Name: string;
begin
  Name := TArgusStrings.Text(TArgusTextId.ProblemsGroup);
  Result := AMessages.GetGroup(Name);
  if (Result = nil) and ACreate then
    Result := AMessages.AddMessageGroup(Name);
end;

procedure TArgusProblemsList.Update(AStore: TArgusProblemStore);
type
  TEntry = record
    FileName: string;
    Problem: TArgusProblem;
  end;
var
  Messages: IOTAMessageServices;
  Target: IOTAMessageGroup;
  Entries: TArray<TEntry>;
  Entry: TEntry;
  FileName: string;
  Problem: TArgusProblem;
  Builder: TStringBuilder;
  Signature: string;
  Total: Integer;
  LineRef: Pointer;
begin
  Entries := nil;
  Total := 0;
  Builder := TStringBuilder.Create;
  try
    for FileName in AStore.Files do
      for Problem in AStore.ForFile(FileName) do
      begin
        if Problem.IsCompiler then
          Continue;
        Inc(Total);
        if Length(Entries) >= MaxEntries then
          Continue;
        Entry.FileName := FileName;
        Entry.Problem := Problem;
        Entries := Entries + [Entry];
        Builder.Append(FileName).Append('|').Append(Problem.StartLine).Append('|').Append(Problem.StartCharacter)
          .Append('|').Append(Ord(Problem.Severity)).Append('|').Append(Problem.Caption).Append(#10);
      end;
    Builder.Append(Total);
    Signature := Builder.ToString;
  finally
    Builder.Free;
  end;
  if Signature = FSignature then
    Exit;
  FSignature := Signature;
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Target := Group(Messages, Length(Entries) > 0);
  if Target = nil then
    Exit;
  Messages.ClearMessageGroup(Target);
  for Entry in Entries do
    Messages.AddToolMessage(Entry.FileName, Entry.Problem.Caption, SeverityText(Entry.Problem.Severity),
      Entry.Problem.StartLine + 1, Entry.Problem.StartCharacter + 1, nil, LineRef, Target);
  if Total > Length(Entries) then
    Messages.AddTitleMessage(TArgusStrings.Fmt(TArgusTextId.ProblemsMore, [Total - Length(Entries)]), Target);
end;

procedure TArgusProblemsList.Clear;
var
  Messages: IOTAMessageServices;
  Target: IOTAMessageGroup;
begin
  if FSignature = '' then
    Exit;
  FSignature := '';
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Target := Group(Messages, False);
  if Target <> nil then
    Messages.ClearMessageGroup(Target);
end;

end.
