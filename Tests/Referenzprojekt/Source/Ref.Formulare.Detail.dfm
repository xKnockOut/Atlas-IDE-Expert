inherited DetailFormular: TDetailFormular
  Caption = 'Detail'
  inherited KopfPanel: TPanel
    inherited TitelLabel: TLabel
      Caption = 'Details'
    end
  end
  object NameEdit: TEdit
    Left = 8
    Top = 56
    Width = 200
    Height = 23
    TabOrder = 1
    OnChange = NameEditChange
  end
  object Anzeige: TRefAnzeige
    Left = 8
    Top = 96
    Width = 200
    Height = 32
    Stil = asSchatten
    Beschriftung = 'Zeichen'
    Verknuepft = NameEdit
  end
end
