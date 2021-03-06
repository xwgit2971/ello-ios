////
///  ForgotPasswordProtocols.swift
//


protocol ForgotPasswordEmailDelegate: class {
    func backAction()
    func validate(email: String)
    func submit(email: String)
}

protocol ForgotPasswordEmailScreenProtocol: class {
    var emailValid: Bool? { get set }
    func showEmailError(_ text: String)
    func hideEmailError()
    func loadingHUD(visible: Bool)
    func resignFirstResponder() -> Bool
    func showSubmitMessage()
}


protocol ForgotPasswordResetDelegate: class {
    func backAction()
    func validate(password: String)
    func submit(password: String)
}
protocol ForgotPasswordResetScreenProtocol: class {
    var passwordValid: Bool? { get set }
    func showFailureMessage()
    func showPasswordError(_ text: String)
    func hidePasswordError()
    func loadingHUD(visible: Bool)
    func resignFirstResponder() -> Bool
}
