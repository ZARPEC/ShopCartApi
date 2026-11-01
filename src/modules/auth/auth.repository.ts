import { getDbPool, sql } from "../../config/database.js";

export class AuthRepository {
  async registrarCliente(
    nombre: string,
    apellidos: string,
    correo: string,
    hash: string,
    telefono?: string | undefined,
  ) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("Nombres", sql.NVarChar(150), nombre)
      .input("Apellidos", sql.NVarChar(150), apellidos)
      .input("CorreoElectronico", sql.VarChar(255), correo)
      .input("PasswordHash", sql.VarChar(255), hash)
      .input("Telefono", sql.VarChar(30), telefono ?? null)
      .execute("dbo.SP_Auth_RegistrarCliente");
    return result.recordset[0];
  }

  async obtenerUsuarioPorCorreo(correo: string) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("CorreoElectronico", sql.VarChar(255), correo)
      .execute("dbo.SP_Auth_ObtenerUsuarioPorCorreo");
    return result.recordset[0] || null;
  }

  async registrarResultadoLogin(
    idUsuario: number,
    esExitoso: boolean,
  ): Promise<{ FueBloqueado: number; IntentosActuales: number }> {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("IDUsuario", sql.Int, idUsuario)
      .input("EsExitoso", sql.Bit, esExitoso)
      .execute("dbo.SP_Auth_RegistrarResultadoLogin");
    return result.recordset[0];
  }

  async guardarRefreshToken(
    idUsuario: number,
    tokenHash: string,
    familia: string,
    expiracion: Date,
    ip?: string,
    userAgent?: string,
  ) {
    const pool = await getDbPool();
    await pool
      .request()
      .input("IDUsuario", sql.Int, idUsuario)
      .input("TokenHash", sql.VarChar(128), tokenHash)
      .input("FamiliaToken", sql.UniqueIdentifier, familia)
      .input("FechaExpiracion", sql.DateTime2(3), expiracion)
      .input("DireccionIP", sql.VarChar(45), ip ?? null)
      .input("AgenteUsuario", sql.NVarChar(300), userAgent ?? null)
      .execute("dbo.SP_Auth_GuardarRefreshToken");
  }

  async rotarRefreshToken(
    tokenHashActual: string,
    nuevoTokenHash: string,
    nuevaExp: Date,
    ip?: string,
    userAgent?: string,
  ) {
    const pool = await getDbPool();
    const result = await pool
      .request()
      .input("TokenHashActual", sql.VarChar(128), tokenHashActual)
      .input("NuevoTokenHash", sql.VarChar(128), nuevoTokenHash)
      .input("NuevaExpiracion", sql.DateTime2(3), nuevaExp)
      .input("DireccionIP", sql.VarChar(45), ip ?? null)
      .input("AgenteUsuario", sql.NVarChar(300), userAgent ?? null)
      .execute("dbo.SP_Auth_RotarRefreshToken");
    return result.recordset[0];
  }

  async revocarRefreshToken(tokenHash: string) {
    const pool = await getDbPool();
    await pool
      .request()
      .input("TokenHash", sql.VarChar(128), tokenHash)
      .execute("dbo.SP_Auth_RevocarRefreshToken");
  }
}
