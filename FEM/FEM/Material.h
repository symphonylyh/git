/**
 * @file Material.h
 * Material class for the element properties.
 *
 * @author Haohang Huang
 * @date Apr 27, 2018
 * @note Material cross-anisotropy added on May 16, 2018.
 */

#ifndef Material_h
#define Material_h

#include "Eigen/Eigen"
#include <vector>

using namespace Eigen;

/** Material class for storing the engineering properties of elements. */
class Material
{
  public:

    /**
     * Custom constructor to create an element material.
     *
     * @param anisotropy A sign for material isotropy. 0 if isotropic, 1 if cross-anisotropic.
     * @param nonlinearity A sign for material linearity. 0 if linear elastic, 1 if nonlinear elastic.
     * @param noTension A sign for no-tension modification. 0 if normal material, 1 if no-tension modification required material (unbound aggregate).
     * @param properties A list of the material property parameters.
     */
    Material(const bool & anisotropy, const bool & nonlinearity, const bool & noTension);

    /**
     * Destructor.
     *
     * @note As an abstract class, the destructor must be virtual.
     */
    virtual ~Material();

    /**
     * Get the modulus of the element.
     *
     * @return The modulus value.
     */
    const double & modulus() const;

    /**
     * Get the stress-strain constitutive matrix of the element.
     *
     * @return The 4-by-4 E matrix.
     */
    const MatrixXd & EMatrix() const;

    /**
     * Compute the stress-dependent E matrix from resilient modulus. Used in nonlinear scheme.
     *
     * @param modulus The stress-dependent resilient modulus.
     * @return The constitutive matrix.
     */
    virtual MatrixXd EMatrix(const double & modulus) const;

    /**
     * Compute the stress-dependent resilient modulus of the element. Used in nonlinear scheme.
     *
     * @param stress The principal stresses in sigma3, sigma2, sigma1 order.
     * @return The stress-dependent resilient modulus computed from models.
     */
    virtual double stressDependentModulus(const VectorXd & stress) const;

    /**
     * Get the body force to be used in the load condition.
     *
     * @return The body force as a 2-by-1 vector for 2D axisymmetric problem.
     */
    const Vector2d & bodyForce() const;

    /**
     * Assign the body force to allow incremental loading in nonlinear scheme.
     *
     * @param force The incremental body force to be assigned.
     */
    void setBodyForce(const Vector2d & force);

    /**
     * Get the thermal strain to be used in the stress computation.
     *
     * @return The thermal strain as a 4-by-1 vector for 2D axisymmetric problem.
     */
    const VectorXd & thermalStrain() const;

    /**
     * Assign the thermal strain to allow incremental loading in nonlinear scheme.
     *
     * @param thermalStrain The incremental thermal strain to be assigned.
     */
    void setThermalStrain(const VectorXd & thermalStrain);

    /** A sign for material isotropy. 0 if isotropic, 1 if cross-anisotropic. */
    bool anisotropy;

    /** A sign for material linearity. 0 if linear elastic, 1 if nonlinear elastic. */
    bool nonlinearity;

    /** A sign for material no-tension modification. 0 if not needed, 1 if needed. */
    bool noTension;

  protected:

    /** The Young's/Resilient modulus. */
    double modulus_;

    /** The 4-by-4 stress-strain constitutive matrix sigma = E * e */
    MatrixXd E_;

    /** The body force (unit weight) */
    Vector2d bodyForce_;

    /** The thermal strain */
    VectorXd thermalStrain_;

};

#endif /* Material_h */
