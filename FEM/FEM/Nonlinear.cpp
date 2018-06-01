/**
 * @file Nonlinear.cpp
 * Implementation of Nonlinear class.
 *
 * @author Haohang Huang
 * @date May 19, 2018
 */

#include "Nonlinear.h"
#include <cmath>
#include <iostream>

Nonlinear::Nonlinear(std::string const & fileName) : Analysis(fileName), damping(0.7) // adjustable damping ratio
{
}

Nonlinear::~Nonlinear()
{
}

void Nonlinear::solve()
{
    // -------------------------------------------------------------------------
    // --------------- Start of Nonlinear Iteration Scheme ---------------------
    // -------------------------------------------------------------------------
    bool nonlinearConvergence = false;
    int i = 0; // for debug print only
    while (!nonlinearConvergence) { // convergence criteria
    //for (int i = 0; i < 10; i++) {
        std::cout << "Nonlinear Iteration No." << i++ << std::endl;
        // Assemble the K and F based on the mesh information. At 1st iteration, the initial guess modulus M0 will be used; later on at iteration i, the stress-dependent modulus updated from (i - 1) iteratiion will be used
        assembleStiffnessAndForce();

        // Solve K U = F
        SimplicialLDLT <SparseMatrix<double> > solver;
        solver.compute(globalStiffness);
        nodalDisp = solver.solve(nodalForce);

        // Traverse each element, compute stress at Gaussian points, and update the modulus for the next (i + 1) iteration (if current iteration is i)
        nonlinearConvergence = nonlinearIteration();
    }
    // After convergence is achieved at the last iteration, the solved displacment
    // is stored in the protected member of Analysis class -- nodalDisp. And
    // globalStiffness & nodalForce are also pre-cached. K, U, F are all knowns
    // and can be used in the following no tension iteration scheme.
    // -------------------------------------------------------------------------
    // -------------------- End of Nonlinear Scheme ----------------------------
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // --------------- Start of No Tension Iteration Scheme --------------------
    // -------------------------------------------------------------------------
    bool tensionConvergence = false;
    SimplicialLDLT <SparseMatrix<double> > solver;
    solver.compute(globalStiffness);
    while (!tensionConvergence) { // convergence criteria
        // Solve K U = F
        // Note 1: the above nonlinear iteration scheme is iteratively solving a
        // series of linear elastic cases, where K should be updated every time.
        // But in the no tension iteration scheme, K remains unchanged as the
        // last iteration in the nonlinear process. We only update the F vector.
        // Note 2: in Eigen, the solver.compute() is a pre-conditioning of matrix,
        // and we can just recycle the solver for current use. Therefore, the
        // solver is placed outside the while loop.
        nodalDisp = solver.solve(nodalForce);

        // Traverse each element, compute stress at Gaussian points, and update the modulus for the next (i + 1) iteration (if current iteration is i)
        tensionConvergence = noTensionIteration();
    }
    // -------------------------------------------------------------------------
    // ----------------  End of No Tension Iteration Scheme --------------------
    // -------------------------------------------------------------------------

    // After both material nonlinearity and granular no tension scheme converge,
    // compute the nodal strain and stress from the final displacment results
    computeStrainAndStress();
    averageStrainAndStress();

}

bool Nonlinear::nonlinearIteration()
{
    bool convergence = true;
    double sumError = 0;
    double sumModulus = 0;

    Element* curr;
    int numNodes; // number of nodes belong to the element
    int numGaussianPt; // number of Gaussian points of the element
    for (int i = 0; i < mesh.elementCount(); i++) {
        curr = mesh.elementArray()[i];
        Material* material = curr->material();
        if (material->nonlinearity) { // compute stress for nonlinear elastic element only, skip all linear elastic ones
            const VectorXi & nodeList = curr->getNodeList();
            numNodes = curr->getSize();
            numGaussianPt = (int)curr->shape()->gaussianPt().size();

            // Assemble the nodal displacement vector for this element
            VectorXd nodeDisp(2 * numNodes);
            for (int j = 0; j < numNodes; j++) {
                nodeDisp(2 * j) = nodalDisp(2 * nodeList(j));
                nodeDisp(2 * j + 1) = nodalDisp(2 * nodeList(j) + 1);
            }

            // Step 1: Compute stress at gaussian points based on cached M & E from last iteration
            // Step 2: Update new modulus based on the stress from step 1 and mix with old modulus via damping ratio
            // Step 3: Cache the modulus to be used in the next iteration
            for (int g = 0; g < numGaussianPt; g++) {
                MatrixXd B = curr->BMatrix(curr->shape()->gaussianPt(g));
                VectorXd strain = B * nodeDisp; // e = B * u
                double modulus_old = (curr->modulusAtGaussPt)(g); // M_(i-1)
                VectorXd stress = material->EMatrix(modulus_old) * (strain - curr->thermalStrain()); // sigma = E_(i-1) * (e - e0), note that the M and E are both from previous iteration

                double modulus_new = material->stressDependentModulus(principalStress(stress)); // M_i
                double modulus = (1 - damping) * modulus_old + damping * modulus_new; // true M_i after applying damping ratio

                (curr->modulusAtGaussPt)(g) = modulus;

                // Convergence criteria
                // Criteria 1: modulus stabilize within 5% at all Gaussian points
                double error = std::abs(modulus - modulus_old);
                if (error / modulus > 0.05)
                    convergence = false;
                // Criteraia 2: Accumulative modulus error within 0.2%
                sumError += error * error;
                sumModulus += modulus * modulus;
                // For Debug Use
                if (i == 37 && g == 1) { // the granular element at centerline
                    // std::cout << "nodelDisp: " << nodeDisp.transpose() << std::endl;
                    // std::cout << "Strain: " << strain.transpose() << std::endl;
                    // std::cout << "E: " << material->EMatrix(modulus_old) << std::endl;
                    // std::cout << "cylindrical stress: " << stress.transpose() << std::endl;
                    // std::cout << "principal stress: " << principalStress(stress).transpose() << std::endl;
                    std::cout << "Old modulus: " << modulus_old << std::endl;
                    std::cout << "New modulus: " << modulus_new << std::endl;
                    std::cout << "True modulus: " << modulus << std::endl;
                }
            }

        }

    }
    std::cout << "Sum Error: " << sumError / sumModulus << std::endl;
    std::cout << "Modulus Element No.37: " << mesh.elementArray()[37]->modulusAtGaussPt(1) << std::endl;
    return (sumError / sumModulus < 0.002 && convergence) ? true : false;

}

bool Nonlinear::noTensionIteration()
{
    // Jiayi's code
    // MatrixXd Nonlinear::compute_no_tension_force() {
    //     MatrixXd newstress = (std::abs(nodalStress) - nodalStress)/2 + 0.1;
    //     VectorXd newforce = VectorXd::Zero(2 * mesh.nodeCount());
    //
    //     Element* curr;
    //     int numNodes; // number of nodes belong to the element
    //     int numGaussianPt; // number of Gaussian points of the element
    //     VectorXd new_local_force;
    //     for (int i = 0; i < mesh.elementCount(); i++) {
    //         curr = mesh.elementArray()[i];
    //         numNodes = curr->getSize();
    //         numGaussianPt = (int)curr->shape()->gaussianPt().size();
    //         for (int j = 0; j < numGaussianPt; j++) {
    //             // sum 2PI * B^T * newforce * |J| * r * W(i)
    //             new_local_force += 2 * M_PI * _BMatrix(i).transpose() * newforce * _jacobianDet(j) * _radius(j) * curr->shape()->gaussianWt(j);
    //         }
    //         // Assemble the force to global force
    //         for (int k = 0; k < numNodes; k++) {
    //             newforce(2 * nodeList(k)) += new_local_force(2 * k);
    //             newforce(2 * nodeList(k) + 1) += new_local_force(2 * k + 1);
    //         }
    //     }
    //     return newforce;
    // }
    // End of Jiayi's code

    // Sample code from Nonlinear::nonlinearIteration()
    bool convergence = true;

    Element* curr;
    int numNodes; // number of nodes belong to the element
    int numGaussianPt; // number of Gaussian points of the element
    for (int i = 0; i < mesh.elementCount(); i++) {
        curr = mesh.elementArray()[i];
        Material* material = curr->material();
        if (material->nonlinearity) { // compute stress for no tension granular element only, skip all HMA/subgrade ones
        // if (material->noTension) { // compute stress for no tension granular element only, skip all HMA/subgrade ones
            // to enable this, several changes need to be made:
            // 1. Input file
            // 0 35 0 1 1 -- 0 - isotropic, 1 - nonlinear, 1 - no-tension correction needed
            // 2. Mesh.cpp
            // the readFromFile function should read in the 0/1 option for no-tension
            // 3. Material.cpp, LinearElastic.cpp, NonlinearElastic.cpp
            // add a new member variable noTension, and modify the constructor accordingly

            const VectorXi & nodeList = curr->getNodeList();
            numNodes = curr->getSize();
            numGaussianPt = (int)curr->shape()->gaussianPt().size();

            // Assemble the nodal displacement vector for this element
            VectorXd nodeDisp(2 * numNodes);
            for (int j = 0; j < numNodes; j++) {
                nodeDisp(2 * j) = nodalDisp(2 * nodeList(j));
                nodeDisp(2 * j + 1) = nodalDisp(2 * nodeList(j) + 1);
            }

            // Step 1: Compute stress at gaussian points based on the nodal force from last iteration
            // Step 2: Please fill this
            // Step 3: Please fill this
            for (int g = 0; g < numGaussianPt; g++) {
                MatrixXd B = curr->BMatrix(curr->shape()->gaussianPt(g));
                VectorXd strain = B * nodeDisp; // e = B * u
                double modulus = (curr->modulusAtGaussPt)(g); // M_(i-1)
                VectorXd stress = material->EMatrix(modulus) * (strain - curr->thermalStrain()); // sigma = E_(i-1) * (e - e0), note that the M and E are both from previous iteration
                VectorXd principal = principalStress(stress);

                // sigma r, sigma theta, sigma z, tau rz is given as a 4x1 column vector at this Gaussian point
                // @TODO no-tension scheme
                VectorXd tensionForce = curr->computeTensionForce(stress); // just an example, need to be modified

                // Assemble the element tension force to global nodal force
                for (int k = 0; k < numNodes; k++) {
                    nodalForce(2 * nodeList(k)) += tensionForce(2 * k);
                    nodalForce(2 * nodeList(k) + 1) += tensionForce(2 * k + 1);
                }

                // Convergence criteria
                if (true) // modify this
                    convergence = false;

            }
        } // corresponding to if(material->noTension)
    }
    return true; // silence warning, please modify this
}

VectorXd Nonlinear::principalStress(const VectorXd & stress) const
{
    MatrixXd tensor(3,3);
    tensor << stress(0), 0, stress(3),
              0, stress(1), 0,
              stress(3), 0, stress(2);
    SelfAdjointEigenSolver<MatrixXd> es(tensor, EigenvaluesOnly);
    return es.eigenvalues();
}
