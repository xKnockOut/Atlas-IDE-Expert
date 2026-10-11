unit Atlas.IDE.Problems.MessageList;

// Liste der Probleme im Meldungsfenster (#398): eigene Gruppe „Atlas-Probleme“,
// je Problem eine Zeile mit Datei, Zeile und Spalte (Doppelklick springt hin).
// Compilermeldungen stehen schon im Reiter „Build“ und fehlen hier. Neu
// aufgebaut wird nur, wenn sich der Inhalt geändert hat; höchstens MaxEntries
// Zeilen. Die Gruppe wird nicht nach vorn geholt.

interface

uses
  System.SysUtils,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store;

type
  TAtlasProblemsList = class
  public const
    MaxEntries = 1000;
  private
    FSignature: string;
  public
    /// <summary>Gruppe nach AStore aufbauen, falls sich etwas geändert hat.</summary>
    procedure Update(AStore: TAtlasProblemStore);
    /// <summary>Gruppe leeren.</summary>
    procedure Clear;
  end;

implementation

uses
  ToolsAPI,
  Atlas.UI.Strings;

function SeverityText(ASeverity: TAtlasProblemSeverity): string;
begin
  case ASeverity of
    TAtlasProblemSeverity.Error:
      Result := TAtlasStrings.Text(TAtlasTextId.SeverityError);
    TAtlasProblemSeverity.Warning:
      Result := TAtlasStrings.Text(TAtlasTextId.SeverityWarning);
    TAtlasProblemSeverity.Information:
      Result := TAtlasStrings.Text(TAtlasTextId.SeverityInformation);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.SeverityHint);
  end;
end;

function Group(const AMessages: IOTAMessageServices; ACreate: Boolean): IOTAMessageGroup;
var
  Name: string;
begin
  Name := TAtlasStrings.Text(TAtlasTextId.ProblemsGroup);
  Result := AMessages.GetGroup(Name);
  if (Result = nil) and ACreate then
    Result := AMessages.AddMessageGroup(Name);
end;

procedure TAtlasProblemsList.Update(AStore: TAtlasProblemStore);
type
  TEntry = record
    FileName: string;
    Problem: TAtlasProblem;
  end;
var
  Messages: IOTAMessageServices;
  Target: IOTAMessageGroup;
  Entries: TArray<TEntry>;
  Entry: TEntry;
  FileName: string;
  Problem: TAtlasProblem;
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
    Messages.AddTitleMessage(TAtlasStrings.Fmt(TAtlasTextId.ProblemsMore, [Total - Length(Entries)]), Target);
end;

procedure TAtlasProblemsList.Clear;
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
