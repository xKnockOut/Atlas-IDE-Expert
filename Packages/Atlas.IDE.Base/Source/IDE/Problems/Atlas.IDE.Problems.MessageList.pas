unit Atlas.IDE.Problems.MessageList;

// Liste der Probleme im Meldungsfenster (#398): eigene Gruppe „Atlas-Probleme“,
// je Problem eine Zeile mit Datei, Zeile und Spalte (Doppelklick springt hin).
// Compilermeldungen stehen schon im Reiter „Build“ und fehlen hier. Neu
// aufgebaut wird nur, wenn sich der Inhalt geändert hat; höchstens MaxEntries
// Zeilen. Die Gruppe wird nicht nach vorn geholt. Ist die Liste abgeschaltet
// (Problems oder ProblemsMessageList aus), verschwindet der Reiter ganz.

interface

uses
  System.SysUtils,
  Atlas.Core.Problems.Store;

type
  TAtlasProblemsList = class
  public const
    cMaxEntries = 1000;
  private
    FSignature: string;
  public
    /// <summary>Gruppe nach AStore aufbauen, falls sich etwas geändert hat.</summary>
    procedure Update(AStore: TAtlasProblemStore);
    /// <summary>Gruppe entfernen (Liste abgeschaltet).</summary>
    procedure Clear;
    /// <summary>Meldungsfenster mit der Gruppe „Atlas-Probleme“ zeigen (Klick auf den Zähler, #509).</summary>
    class procedure ShowList; static;
  end;

implementation

uses
  Atlas.Core.Problems.Contract,
  ToolsAPI,
  Atlas.UI.Problems.Strings;

function SeverityText(ASeverity: TAtlasProblemSeverity): string;
begin
  case ASeverity of
    TAtlasProblemSeverity.Error:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.SeverityError);
    TAtlasProblemSeverity.Warning:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.SeverityWarning);
    TAtlasProblemSeverity.Information:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.SeverityInformation);
  else
    Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.SeverityHint);
  end;
end;

function Group(const AMessages: IOTAMessageServices; ACreate: Boolean): IOTAMessageGroup;
var
  mName: string;
begin
  mName := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsGroup);
  Result := AMessages.GetGroup(mName);
  if (Result = nil) and ACreate then
  begin
    Result := AMessages.AddMessageGroup(mName);
  end;
end;

type
  TListEntry = record
    FileName: string;
    Problem: TAtlasProblem;
  end;

/// <summary>Höchstens AMax Befunde ohne Compilermeldungen in AEntries, alle in ATotal; Ergebnis ist die Signatur
/// des Stands (gleich = nichts zu tun).</summary>
function CollectEntries(AStore: TAtlasProblemStore; AMax: Integer; out AEntries: TArray<TListEntry>;
  out ATotal: Integer): string;
var
  mEntry: TListEntry;
  mFileName: string;
  mProblem: TAtlasProblem;
  mBuilder: TStringBuilder;
begin
  AEntries := nil;
  ATotal := 0;
  mBuilder := TStringBuilder.Create;
  try
    for mFileName in AStore.Files do
    begin
      for mProblem in AStore.ForFile(mFileName) do
      begin
        if mProblem.IsCompiler then
        begin
          Continue;
        end;
        Inc(ATotal);
        if Length(AEntries) < AMax then
        begin
          mEntry.FileName := mFileName;
          mEntry.Problem := mProblem;
          AEntries := AEntries + [mEntry];
          mBuilder.Append(mFileName).Append('|').Append(mProblem.StartLine).Append('|')
            .Append(mProblem.StartCharacter).Append('|').Append(Ord(mProblem.Severity)).Append('|')
            .Append(mProblem.Caption).Append(#10);
        end;
      end;
    end;
    mBuilder.Append(ATotal);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

procedure TAtlasProblemsList.Update(AStore: TAtlasProblemStore);
var
  mMessages: IOTAMessageServices;
  mTarget: IOTAMessageGroup;
  mEntries: TArray<TListEntry>;
  mEntry: TListEntry;
  mSignature: string;
  mTotal: Integer;
  mLineRef: Pointer;
begin
  mSignature := CollectEntries(AStore, cMaxEntries, mEntries, mTotal);
  if mSignature = FSignature then
  begin
    Exit;
  end;
  FSignature := mSignature;
  mTarget := nil;
  if Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    mTarget := Group(mMessages, Length(mEntries) > 0);
  end;
  if mTarget = nil then
  begin
    Exit;
  end;
  mMessages.ClearMessageGroup(mTarget);
  for mEntry in mEntries do
  begin
    mMessages.AddToolMessage(mEntry.FileName, mEntry.Problem.Caption, SeverityText(mEntry.Problem.Severity),
      mEntry.Problem.StartLine + 1, mEntry.Problem.StartCharacter + 1, nil, mLineRef, mTarget);
  end;
  if mTotal > Length(mEntries) then
  begin
    mMessages.AddTitleMessage(TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsMore, [mTotal - Length(mEntries)]),
      mTarget);
  end;
end;

class procedure TAtlasProblemsList.ShowList;
var
  mMessages: IOTAMessageServices;
begin
  if Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    mMessages.ShowMessageView(Group(mMessages, False));
  end;
end;

procedure TAtlasProblemsList.Clear;
var
  mMessages: IOTAMessageServices;
  mTarget: IOTAMessageGroup;
begin
  if FSignature = '' then
  begin
    Exit;
  end;
  FSignature := '';
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mTarget := Group(mMessages, False);
  if mTarget <> nil then
  begin
    mMessages.RemoveMessageGroup(mTarget);
  end;
end;

end.
