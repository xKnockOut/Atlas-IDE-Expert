unit Atlas.Core.Signature.Controller;

// Ablauf des Parameter-Hints ohne Fenster (#436, #437): hält die Signaturen
// eines Aufrufs, den aktiven Parameter und die gezeigte Überladung.
//   - Start: die vom Server gewählte Signatur, sonst die kürzeste, die zum
//     aktiven Parameter passt.
//   - Weitertippen: Übersteigt der aktive Parameter die gezeigte Signatur, wechselt
//     der Hint zur nächsten passenden (z. B. Format mit TFormatSettings). Von Hand
//     gewählte Überladungen (Alt+↑/↓) bleiben erreichbar, auch wenn sie nicht passen.
//   - Argumenttypen (#498): Meldet der Server, dass ein bisheriges Argument nicht zum Parametertyp passt
//     (TypeMismatch), passt die Überladung nicht, erscheint gedämpft und wird nicht vorgewählt. Die Zahl der
//     Argumente zählt weiter lokal.

interface

uses
  System.SysUtils,
  Atlas.Core.Signature.Contract;

type
  IAtlasSignatureView = interface
    ['{2A6C9E14-7B3D-4F58-9C21-E5D84B7A0F36}']
    /// <summary>Zeigt bzw. aktualisiert den Hint. AParameter kann über die Parameter der Signatur
    /// hinausgehen (dann ist keiner hervorgehoben).</summary>
    procedure ShowSignature(const AHelp: TAtlasSignatureHelp; ASignature, AParameter: Integer);
    procedure HideSignature;
  end;

  TAtlasSignatureController = class
  private
    FView: IAtlasSignatureView;
    FHelp: TAtlasSignatureHelp;
    FSignature: Integer;
    FParameter: Integer;
    FActive: Boolean;
    function Fits(ASignature, AParameter: Integer): Boolean;
    function FirstFitting(AParameter: Integer): Integer;
    procedure Update;
  public
    constructor Create(const AView: IAtlasSignatureView);
    /// <summary>Zeigt AHelp; AParameter ist der lokal gezählte aktive Parameter.</summary>
    procedure Show(const AHelp: TAtlasSignatureHelp; AParameter: Integer);
    /// <summary>Der aktive Parameter hat sich beim Tippen geändert.</summary>
    procedure UpdateParameter(AParameter: Integer);
    procedure NextOverload;
    procedure PreviousOverload;
    /// <summary>Wählt die Überladung AIndex (Klick im Hint).</summary>
    procedure SelectOverload(AIndex: Integer);
    /// <summary>Passt der aktive Parameter zur Überladung AIndex (sonst gedämpft gezeigt)?</summary>
    function OverloadFits(AIndex: Integer): Boolean;
    procedure Close;
    /// <summary>Reicht ASignature für so viele Argumente (AParameter 0-basiert)? Nur die Anzahl: Der erste
    /// Parameter passt immer, auch bei leeren Klammern.</summary>
    class function CountFits(const ASignature: TAtlasSignature; AParameter: Integer): Boolean; static;
    /// <summary>Fehlerzustand (#439): Keine Überladung erlaubt so viele Argumente; Typen zählen nicht.</summary>
    class function TooManyArguments(const AHelp: TAtlasSignatureHelp; AParameter: Integer): Boolean; static;
    property Active: Boolean read FActive;
    property Signature: Integer read FSignature;
    property Parameter: Integer read FParameter;
    property Help: TAtlasSignatureHelp read FHelp;
  end;

implementation

{ TAtlasSignatureController }

constructor TAtlasSignatureController.Create(const AView: IAtlasSignatureView);
begin
  inherited Create;
  FView := AView;
end;

class function TAtlasSignatureController.CountFits(const ASignature: TAtlasSignature; AParameter: Integer): Boolean;
begin
  Result := (AParameter = 0) or (AParameter < Length(ASignature.Parameters));
end;

class function TAtlasSignatureController.TooManyArguments(const AHelp: TAtlasSignatureHelp;
  AParameter: Integer): Boolean;
var
  Signature: TAtlasSignature;
begin
  Result := Length(AHelp.Signatures) > 0;
  for Signature in AHelp.Signatures do
    if CountFits(Signature, AParameter) then
      Exit(False);
end;

function TAtlasSignatureController.Fits(ASignature, AParameter: Integer): Boolean;
begin
  // Nach der Anzahl; ein Argument mit unverträglichem Typ passt nie (#498).
  Result := CountFits(FHelp.Signatures[ASignature], AParameter) and not FHelp.Signatures[ASignature].TypeMismatch;
end;

function TAtlasSignatureController.FirstFitting(AParameter: Integer): Integer;
var
  Index, Best: Integer;
begin
  // Die kürzeste passende Signatur; gibt es keine, die längste.
  Best := -1;
  for Index := 0 to High(FHelp.Signatures) do
    if Fits(Index, AParameter) and ((Best < 0) or
      (Length(FHelp.Signatures[Index].Parameters) < Length(FHelp.Signatures[Best].Parameters))) then
      Best := Index;
  if Best < 0 then
    for Index := 0 to High(FHelp.Signatures) do
      if (Best < 0) or (Length(FHelp.Signatures[Index].Parameters) > Length(FHelp.Signatures[Best].Parameters)) then
        Best := Index;
  Result := Best;
end;

procedure TAtlasSignatureController.Show(const AHelp: TAtlasSignatureHelp; AParameter: Integer);
begin
  if AHelp.IsEmpty then
  begin
    Close;
    Exit;
  end;
  FHelp := AHelp;
  FParameter := AParameter;
  if (AHelp.ActiveSignature >= 0) and (AHelp.ActiveSignature <= High(AHelp.Signatures)) and
    Fits(AHelp.ActiveSignature, AParameter) then
    FSignature := AHelp.ActiveSignature
  else
    FSignature := FirstFitting(AParameter);
  FActive := True;
  Update;
end;

procedure TAtlasSignatureController.UpdateParameter(AParameter: Integer);
begin
  if not FActive or (AParameter = FParameter) then
    Exit;
  FParameter := AParameter;
  // Automatischer Wechsel nur, wenn die gezeigte Variante nicht mehr passt (#437).
  if not Fits(FSignature, AParameter) then
    FSignature := FirstFitting(AParameter);
  Update;
end;

procedure TAtlasSignatureController.NextOverload;
begin
  if not FActive or (Length(FHelp.Signatures) < 2) then
    Exit;
  FSignature := (FSignature + 1) mod Length(FHelp.Signatures);
  Update;
end;

procedure TAtlasSignatureController.PreviousOverload;
begin
  if not FActive or (Length(FHelp.Signatures) < 2) then
    Exit;
  FSignature := (FSignature + Length(FHelp.Signatures) - 1) mod Length(FHelp.Signatures);
  Update;
end;

procedure TAtlasSignatureController.SelectOverload(AIndex: Integer);
begin
  if not FActive or (AIndex < 0) or (AIndex > High(FHelp.Signatures)) or (AIndex = FSignature) then
    Exit;
  FSignature := AIndex;
  Update;
end;

function TAtlasSignatureController.OverloadFits(AIndex: Integer): Boolean;
begin
  Result := FActive and (AIndex >= 0) and (AIndex <= High(FHelp.Signatures)) and Fits(AIndex, FParameter);
end;

procedure TAtlasSignatureController.Close;
begin
  if not FActive then
    Exit;
  FActive := False;
  FHelp := Default(TAtlasSignatureHelp);
  FView.HideSignature;
end;

procedure TAtlasSignatureController.Update;
begin
  FView.ShowSignature(FHelp, FSignature, FParameter);
end;

end.
